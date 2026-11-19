package de.danielkononov.hiwiski.admin.internal;

import de.danielkononov.hiwiski.admin.InstanceRestored;
import de.danielkononov.hiwiski.admin.RestoreCarryOver;
import de.danielkononov.hiwiski.identity.SetupGate;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.identity.SignInState;
import de.danielkononov.hiwiski.platform.InstanceSettings;
import de.danielkononov.hiwiski.platform.SettingKey;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import javax.sql.DataSource;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.jooq.DSLContext;
import org.jooq.Field;
import org.jooq.Table;
import org.jooq.impl.DSL;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.ApplicationEventPublisher;
import org.jspecify.annotations.Nullable;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.ObjectMapper;

/**
 * Restores an unpacked archive of this version or any older one.
 *
 * <p>The running schema is not touched until the end:
 *
 * <ol>
 *   <li>A staging schema is migrated exactly to the archive's schema version.
 *   <li>The archive's rows go into it, table by table, in foreign-key order.
 *   <li>Flyway migrates it on to the current version -- every data migration runs on the
 *       restored data as it ran on every other instance.
 *   <li>In one transaction, the tables of {@code public} are emptied and filled from the
 *       staging schema, and what is not taken from the archive is carried over.
 * </ol>
 *
 * <p>An archive of the same version takes the same path with nothing to migrate: there
 * is one restore, not two. Anything failing before the last step leaves the instance as
 * it was.
 *
 * <p>Filled from the staging schema rather than swapped for it: {@code pg_trgm} lives in
 * {@code public}, and a schema renamed away would take the extension -- and the search
 * indexes of the staging schema that use it -- with it when dropped.
 */
@Component
class StagingRestore {

    private static final Logger log = LoggerFactory.getLogger(StagingRestore.class);

    static final String STAGING = "hiwiski_restore";

    /**
     * Settings the running server keeps: its backup key -- an old archive must not bring
     * back a password changed since --, the version it runs and how its backups went.
     */
    private static final List<String> KEPT_SETTINGS = List.of(
            SettingKey.BACKUP_KEY_RECIPIENT,
            SettingKey.BACKUP_KEY_SLOT,
            SettingKey.BACKUP_FAILURE,
            SettingKey.SERVER_LAST_VERSION);

    private final DSLContext db;
    private final DataSource dataSource;
    private final ObjectMapper json;
    private final TransactionTemplate transaction;
    private final InstanceSettings settings;
    private final BackupKeys keys;
    private final ApplicationEventPublisher events;
    private final Path mediaPath;

    /** Passwords and revoked devices: carried over a restore, not taken from the archive. */
    private final SignInState signIns;

    /** The domain modules' bearer secrets -- board and feed addresses -- likewise. */
    private final List<RestoreCarryOver> carriedOver;

    private final SetupGate setup;

    StagingRestore(
            DSLContext db,
            DataSource dataSource,
            ObjectMapper json,
            PlatformTransactionManager transactions,
            InstanceSettings settings,
            BackupKeys keys,
            ApplicationEventPublisher events,
            @Value("${hiwiski.media-path}") String mediaPath,
            SignInState signIns,
            List<RestoreCarryOver> carriedOver,
            SetupGate setup) {
        this.setup = setup;
        this.db = db;
        this.dataSource = dataSource;
        this.json = json;
        this.transaction = new TransactionTemplate(transactions);
        this.settings = settings;
        this.keys = keys;
        this.events = events;
        this.mediaPath = Path.of(mediaPath);
        this.signIns = signIns;
        this.carriedOver = List.copyOf(carriedOver);
    }

    /**
     * The archive's key, for a restore on a fresh server: it has none of its own, and
     * the backups from then on open with the password just typed.
     */
    record Adoption(String recipient, String identity, String password) {}

    record Outcome(UUID instanceId, long rows) {}

    /**
     * Replaces <strong>everything</strong> and regenerates the instance identifier.
     *
     * <p>Afterwards every device has to sync from scratch: the sequence numbers no longer
     * match what the devices have seen. Without this identifier they would silently keep
     * working on a state that no longer exists — the worst data loss imaginable in this
     * app.
     *
     * <p><strong>Who may sign in is not restored.</strong> Passwords, forced changes,
     * disabled members and revoked devices stay as they are now: a phone revoked after
     * the backup or a password changed since must not come back with Sunday's data.
     * Devices registered since the backup -- this one, as a rule -- stay signed in.
     *
     * @param unpacked the decrypted archive; its images are moved in after the commit
     */
    Outcome restore(Path unpacked, Manifest manifest, @Nullable Adoption adoption) {
        MigrationVersion archived = MigrationVersion.fromVersion(manifest.schemaVersion());
        // The schema starts at the baseline. Migrated to anything before it, the staging
        // schema has no tables, nothing of the archive goes in, and the last step would
        // empty the instance for it. No server ever wrote such an archive.
        if (archived.compareTo(BaselineTakeover.BASELINE) < 0) {
            throw HiwiskiException.invalid("admin.backup_invalid");
        }
        try {
            dropStaging();
            migrateStaging(archived);
            transaction.executeWithoutResult(status -> fillStaging(unpacked.resolve(BackupWriter.DATA_PREFIX)));
            migrateStaging(MigrationVersion.LATEST);
            Outcome outcome = transaction.execute(status -> swap(unpacked, adoption));
            log.info(
                    "restored backup {} (schema {}) with {} rows; new instance id {}",
                    manifest.id(),
                    manifest.schemaVersion(),
                    outcome.rows(),
                    outcome.instanceId());
            return outcome;
        } finally {
            dropStaging();
        }
    }

    private void migrateStaging(MigrationVersion target) {
        Flyway.configure()
                .dataSource(dataSource)
                .schemas(STAGING)
                .createSchemas(true)
                .locations("classpath:db/migration")
                .target(target)
                .cleanDisabled(true)
                .load()
                .migrate();
    }

    private void dropStaging() {
        db.execute("drop schema if exists " + DSL.name(STAGING) + " cascade");
    }

    /**
     * The archive's rows into the staging schema. Emptied first: the migrations seed
     * rows of their own -- the counters, the default categories -- that the archive
     * brings as well.
     */
    private void fillStaging(Path data) {
        List<Table<?>> tables = ArchiveTables.of(db, STAGING);
        // Empty backwards, fill forwards: that way every referenced row is already there
        // when the referencing one arrives.
        for (int i = tables.size() - 1; i >= 0; i--) {
            db.deleteFrom(tables.get(i)).execute();
        }
        Set<String> known = new HashSet<>();
        int filled = 0;
        try {
            for (Table<?> table : tables) {
                known.add(table.getName());
                Path entry = data.resolve(table.getName() + ".jsonl");
                if (!Files.isRegularFile(entry)) {
                    continue;
                }
                filled++;
                List<Field<?>> columns = ArchiveTables.columns(table);
                if (ArchiveTables.selfReferences(table).isEmpty()) {
                    // Line by line: years of change log and revisions do not fit in a
                    // small server's heap all at once.
                    try (var lines = Files.lines(entry, StandardCharsets.UTF_8)) {
                        for (String line : (Iterable<String>) lines::iterator) {
                            if (!line.isBlank()) {
                                ArchiveTables.insert(db, table, columns, row(line));
                            }
                        }
                    }
                    continue;
                }
                // A table that refers to itself needs all its rows to put parents first.
                List<Map<String, Object>> rows = new ArrayList<>();
                try (var lines = Files.lines(entry, StandardCharsets.UTF_8)) {
                    for (String line : (Iterable<String>) lines::iterator) {
                        if (!line.isBlank()) {
                            rows.add(row(line));
                        }
                    }
                }
                for (Map<String, Object> row : ArchiveTables.parentsFirst(table, rows)) {
                    ArchiveTables.insert(db, table, columns, row);
                }
            }
            if (filled == 0) {
                // An archive that brings no table of this schema would replace the
                // family's data by nothing.
                throw HiwiskiException.invalid("admin.backup_invalid");
            }
            if (Files.isDirectory(data)) {
                try (var files = Files.list(data)) {
                    var unknown = files.map(file -> file.getFileName().toString().replace(".jsonl", ""))
                            .filter(name -> !known.contains(name))
                            .collect(Collectors.toSet());
                    if (!unknown.isEmpty()) {
                        // At its own schema version, an archive names no table the
                        // schema does not have -- unless it was made by hand.
                        log.warn("restore: the archive names tables its schema does not have: {}", unknown);
                    }
                }
            }
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private Map<String, Object> row(String line) {
        return json.readValue(line, new TypeReference<Map<String, Object>>() {});
    }

    /** The one step that changes the running instance -- all of it, or none. */
    private Outcome swap(Path unpacked, @Nullable Adoption adoption) {
        if (adoption != null) {
            // Still nobody's, and nobody else's until this is committed: the wizard may
            // have run while the archive was unpacked.
            setup.requireFreshAndHold();
        }
        SignInState.Snapshot signedIn = signIns.capture();
        List<RestoreCarryOver.Snapshot> secrets =
                carriedOver.stream().map(RestoreCarryOver::capture).toList();
        Map<String, Optional<String>> kept = new LinkedHashMap<>();
        KEPT_SETTINGS.forEach(key -> kept.put(key, settings.find(key)));
        Optional<String> ownFamily = settings.find(SettingKey.FAMILY_ID);

        List<Table<?>> live = ArchiveTables.of(db, "public");
        Map<String, Table<?>> staged = ArchiveTables.of(db, STAGING).stream()
                .collect(Collectors.toMap(Table::getName, table -> table));
        for (int i = live.size() - 1; i >= 0; i--) {
            db.deleteFrom(live.get(i)).execute();
        }
        long rows = 0;
        for (Table<?> table : live) {
            Table<?> source = staged.get(table.getName());
            if (source == null) {
                continue;
            }
            List<Field<?>> columns = ArchiveTables.columns(table);
            List<Field<?>> from = columns.stream()
                    .<Field<?>>map(field -> DSL.field(DSL.name(STAGING, table.getName(), field.getName())))
                    .toList();
            // One statement per table: Postgres checks a foreign key at the statement's
            // end, so a page may come before its parent here.
            rows += db.insertInto(table, columns).select(DSL.select(from).from(source)).execute();
        }

        signIns.carryOver(signedIn);
        for (int i = 0; i < carriedOver.size(); i++) {
            carriedOver.get(i).carryOver(secrets.get(i));
        }
        kept.forEach((key, value) -> value.ifPresentOrElse(
                present -> settings.put(key, present, null), () -> settings.remove(key)));
        if (adoption == null) {
            // A running server stays the family it is; a fresh one takes the archive's.
            ownFamily.ifPresent(id -> settings.put(SettingKey.FAMILY_ID, id, null));
        }
        if (adoption != null) {
            keys.adopt(adoption.recipient(), adoption.identity(), adoption.password());
        }

        UUID instanceId = UUID.randomUUID();
        settings.put(SettingKey.INSTANCE_ID, instanceId.toString(), null);
        afterCommit(unpacked.resolve(BackupWriter.MEDIA_PREFIX));

        // What is derived has to be rebuilt afterwards -- the search index is not in the
        // archive. An event and not a call: `admin` does not know `search`.
        events.publishEvent(new InstanceRestored(instanceId));
        return new Outcome(instanceId, rows);
    }

    /**
     * The images follow the data only once it is committed.
     *
     * <p>Written while the archive was read, a failed restore rolled the database back
     * but left the images replaced; and images uploaded after the backup stayed on disk
     * with nothing pointing to them.
     */
    private void afterCommit(Path restored) {
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                try {
                    replaceMedia(restored);
                } catch (IOException e) {
                    log.error("restore: the images could not be put back from {}", restored, e);
                }
            }
        });
    }

    private void replaceMedia(Path restored) throws IOException {
        Files.createDirectories(mediaPath);
        Set<Path> kept = new HashSet<>();
        if (Files.isDirectory(restored)) {
            try (var files = Files.walk(restored)) {
                for (Path source : files.filter(Files::isRegularFile).toList()) {
                    Path relative = restored.relativize(source);
                    Path target = mediaPath.resolve(relative.toString());
                    Files.createDirectories(target.getParent());
                    Files.move(source, target, java.nio.file.StandardCopyOption.REPLACE_EXISTING);
                    kept.add(relative);
                }
            }
        }
        try (var files = Files.walk(mediaPath)) {
            for (Path existing : files.filter(Files::isRegularFile).toList()) {
                if (!kept.contains(mediaPath.relativize(existing))) {
                    Files.deleteIfExists(existing);
                }
            }
        }
    }
}
