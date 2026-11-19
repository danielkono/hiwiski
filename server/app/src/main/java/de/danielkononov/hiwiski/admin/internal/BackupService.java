package de.danielkononov.hiwiski.admin.internal;

import de.danielkononov.hiwiski.identity.SetupGate;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.platform.InstanceSettings;
import de.danielkononov.hiwiski.platform.RestoreInProgress;
import de.danielkononov.hiwiski.platform.SettingKey;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.file.AccessDeniedException;
import java.nio.file.FileSystemException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.Duration;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.locks.ReentrantLock;
import org.jooq.DSLContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.info.BuildProperties;
import org.springframework.http.HttpStatus;
import org.jspecify.annotations.Nullable;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.ObjectMapper;

/**
 * Backup and restore.
 *
 * <p>One backup or restore at a time: a restore backs up first, and the scheduled one
 * waits for neither -- it tries again a few minutes later.
 */
@Service
class BackupService {

    private static final Logger log = LoggerFactory.getLogger(BackupService.class);

    /** An upload nothing followed is deleted after this long. */
    static final Duration UPLOAD_LIFETIME = Duration.ofHours(1);

    private static final String UPLOAD_SUFFIX = ".upload";

    private final DSLContext db;
    private final ObjectMapper json;
    private final InstanceSettings settings;
    private final @Nullable BuildProperties build;
    private final BackupKeys keys;
    private final StagingRestore staging;
    private final SetupGate setup;
    private final RestoreInProgress restoring;
    private final BackupDirectory directory;
    private final BackupWriter writer;
    private final ArchiveReader reader;

    /**
     * Uploads and unpacked archives: next to the images, not in the backup directory --
     * an uploaded file is never kept there, and a restore moves the images in rather
     * than copying them across disks.
     */
    private final Path work;

    private final TransactionTemplate snapshot;
    private final PlatformTransactionManager transactions;
    private final ReentrantLock running = new ReentrantLock();

    BackupService(
            DSLContext db,
            ObjectMapper json,
            InstanceSettings settings,
            @Nullable BuildProperties build,
            @Value("${hiwiski.backup-path}") String backupPath,
            @Value("${hiwiski.media-path}") String mediaPath,
            PlatformTransactionManager transactions,
            BackupKeys keys,
            StagingRestore staging,
            SetupGate setup,
            RestoreInProgress restoring) {
        this.db = db;
        this.json = json;
        this.settings = settings;
        this.build = build;
        this.keys = keys;
        this.staging = staging;
        this.setup = setup;
        this.restoring = restoring;
        this.directory = new BackupDirectory(Path.of(backupPath), json);
        this.writer = new BackupWriter(json, Path.of(mediaPath));
        this.reader = new ArchiveReader(json);
        Path media = Path.of(mediaPath).toAbsolutePath();
        this.work = (media.getParent() == null ? media : media.getParent()).resolve(".hiwiski-work");
        // One snapshot for all tables: under the default isolation every table was read
        // at its own moment, and a list and a task created while the backup ran could
        // land in the archive as the task without its list -- an archive whose restore
        // fails.
        this.transactions = transactions;
        this.snapshot = new TransactionTemplate(transactions);
        snapshot.setReadOnly(true);
        snapshot.setIsolationLevel(TransactionDefinition.ISOLATION_REPEATABLE_READ);
    }

    BackupDirectory directory() {
        return directory;
    }

    // --- Backup ------------------------------------------------------------------

    /**
     * Backs up now. A failure is kept with its reason until the next backup succeeds,
     * and answered with {@code 503 admin.backup_failed}.
     */
    BackupArchive create(BackupReason reason) {
        running.lock();
        try {
            BackupKeys.Current key;
            BackupArchive archive;
            try {
                key = keys.require();
                archive = snapshot.execute(status -> {
                    try {
                        return writer.write(db, directory, reason, serverVersion(), null, key.recipient(), key.slot());
                    } catch (IOException e) {
                        throw new UncheckedIOException(e);
                    }
                });
            } catch (RuntimeException e) {
                FailureReason failure = FailureReason.of(e);
                log.error("backup ({}) failed: {}", reason, failure, e);
                recordFailure(failure, reason);
                if (e instanceof HiwiskiException hiwiski) {
                    throw hiwiski;
                }
                throw new HiwiskiException(
                        HttpStatus.SERVICE_UNAVAILABLE, "admin.backup_failed", Map.of("reason", failure.name()));
            }
            settings.remove(SettingKey.BACKUP_FAILURE);
            directory.prune(schedule().keep());
            return archive;
        } finally {
            running.unlock();
        }
    }

    /**
     * The scheduled backup, if one is due. Skipped while another backup or a restore
     * runs -- the next check comes a few minutes later.
     */
    void createIfDue(Instant now) {
        if (!setup.completed() || !running.tryLock()) {
            return;
        }
        try {
            if (keys.current().isEmpty()) {
                // Nothing can be encrypted yet; the settings say so until a password is set.
                if (settings.find(SettingKey.BACKUP_FAILURE).isEmpty()) {
                    recordFailure(FailureReason.NO_BACKUP_PASSWORD, BackupReason.SCHEDULED);
                }
                return;
            }
            Instant newest = directory.list().stream()
                    .findFirst()
                    .map(archive -> archive.header().info().createdAt())
                    .orElse(null);
            if (schedule().due(now, newest)) {
                try {
                    create(BackupReason.SCHEDULED);
                } catch (RuntimeException e) {
                    // Kept as the failure; the log has it already.
                }
            }
        } finally {
            running.unlock();
        }
    }

    List<BackupArchive> list() {
        return directory.list();
    }

    BackupSchedule schedule() {
        return BackupSchedule.of(settings);
    }

    /** The status line: the last backup, the next one due, and a failure since. */
    Status status(Instant now) {
        var newest = directory.list().stream().findFirst().map(archive -> archive.header().info().createdAt());
        return new Status(
                newest.orElse(null),
                schedule().nextDue(now),
                failure().orElse(null),
                directory.path().toString(),
                keys.current().isPresent());
    }

    record Status(
            @Nullable Instant lastBackupAt,
            Instant nextDueAt,
            @Nullable Failure failure,
            String directory,
            boolean passwordSet) {}

    record Failure(Instant at, FailureReason reason, BackupReason trigger) {}

    /** Whether {@code recipient} is the key new archives are encrypted to. */
    boolean isCurrentKey(String recipient) {
        return keys.current().map(current -> current.recipient().equals(recipient)).orElse(false);
    }

    private void recordFailure(FailureReason reason, BackupReason trigger) {
        Map<String, String> fields = new LinkedHashMap<>();
        fields.put("at", Instant.now().toString());
        fields.put("reason", reason.name());
        fields.put("trigger", trigger.name());
        settings.put(SettingKey.BACKUP_FAILURE, json.writeValueAsString(fields), null);
    }

    private Optional<Failure> failure() {
        return settings.find(SettingKey.BACKUP_FAILURE).flatMap(value -> {
            try {
                Map<String, String> fields = json.readValue(value, new TypeReference<>() {});
                return Optional.of(new Failure(
                        Instant.parse(fields.get("at")),
                        FailureReason.valueOf(fields.get("reason")),
                        BackupReason.valueOf(fields.get("trigger"))));
            } catch (RuntimeException e) {
                return Optional.empty();
            }
        });
    }

    /** The archive to download, or {@code 404 admin.backup_not_found}. */
    BackupArchive archive(String id) {
        return directory.find(id).orElseThrow(() -> HiwiskiException.notFound("admin.backup_not_found", "id", id));
    }

    // --- Uploads -------------------------------------------------------------------

    record Upload(String id, long bytes) {}

    /** Streams an uploaded archive to a staging file -- never into the backup directory. */
    Upload upload(InputStream body) {
        String id = UUID.randomUUID().toString();
        try {
            Files.createDirectories(uploads());
            Path file = uploads().resolve(id + UPLOAD_SUFFIX);
            try {
                Files.copy(body, file);
            } catch (IOException | RuntimeException e) {
                Files.deleteIfExists(file);
                throw e;
            }
            if (ArchiveHeader.read(file, json).isEmpty()) {
                Files.deleteIfExists(file);
                throw HiwiskiException.invalid("admin.backup_invalid");
            }
            return new Upload(id, Files.size(file));
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /** An upload, or {@code 404 admin.backup_upload_not_found}. */
    Path uploaded(String id) {
        try {
            UUID.fromString(id);
        } catch (IllegalArgumentException e) {
            throw HiwiskiException.notFound("admin.backup_upload_not_found", "id", id);
        }
        Path file = uploads().resolve(id + UPLOAD_SUFFIX);
        if (!Files.isRegularFile(file)) {
            throw HiwiskiException.notFound("admin.backup_upload_not_found", "id", id);
        }
        return file;
    }

    /** Uploads nothing followed, an hour after. */
    @Scheduled(fixedDelay = 10 * 60 * 1000)
    void removeStaleUploads() {
        if (!Files.isDirectory(uploads())) {
            return;
        }
        Instant cutoff = Instant.now().minus(UPLOAD_LIFETIME);
        try (var files = Files.list(uploads())) {
            for (Path file : files.toList()) {
                if (Files.getLastModifiedTime(file).toInstant().isBefore(cutoff)) {
                    Files.deleteIfExists(file);
                }
            }
        } catch (IOException e) {
            log.warn("could not remove stale uploads", e);
        }
    }

    private Path uploads() {
        return work.resolve("uploads");
    }

    // --- Preview and restore -------------------------------------------------------

    record Preview(Manifest manifest, long bytes) {}

    /**
     * What a restore of {@code file} would bring back. The password comes first: a wrong
     * one shows up here, before anything is replaced.
     */
    Preview inspect(Path file, String password) {
        String identity = ArchiveReader.unlock(reader.header(file), password);
        Manifest manifest = reader.manifest(file, identity);
        requireNotNewer(manifest);
        // On a fresh server any family's archive is welcome -- that is what it is for.
        if (setup.completed()) {
            requireOwnFamily(manifest);
        }
        try {
            return new Preview(manifest, Files.size(file));
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /**
     * Restores {@code file} on this running instance. The current state is backed up
     * first -- after the archive is unpacked, so the backup's retention cannot remove
     * the archive being restored.
     */
    StagingRestore.Outcome restore(Path file, String password) {
        running.lock();
        try {
            keys.require();
            String identity = ArchiveReader.unlock(reader.header(file), password);
            // From the right password on, the instance is read-only for everyone --
            // the backup before is taken of a state that no longer changes.
            restoring.begin();
            waitForWriters();
            return withUnpacked(file, identity, (unpacked, manifest) -> {
                requireOwnFamily(manifest);
                create(BackupReason.BEFORE_RESTORE);
                return staging.restore(unpacked, manifest, null);
            });
        } finally {
            restoring.end();
            running.unlock();
        }
    }

    /**
     * Sets up a fresh instance from {@code file}: members, groups and the administrator
     * come from the archive; so does the backup key, wrapped with the password just
     * typed. There is nothing to back up before.
     */
    StagingRestore.Outcome restoreOnFreshInstance(Path file, String password) {
        running.lock();
        try {
            setup.requireFresh();
            ArchiveHeader header = reader.header(file);
            String identity = ArchiveReader.unlock(header, password);
            var adoption = new StagingRestore.Adoption(header.info().recipient(), identity, password);
            return withUnpacked(file, identity, (unpacked, manifest) -> staging.restore(unpacked, manifest, adoption));
        } finally {
            running.unlock();
        }
    }

    /**
     * Lets the changes already on their way finish. A push that passed the gate just
     * before it closed still writes; every writer takes the sequence counter's row lock
     * until it commits, so taking it once waits for all of them -- and the backup before
     * the restore holds what they wrote.
     */
    private void waitForWriters() {
        new TransactionTemplate(transactions)
                .executeWithoutResult(status -> db.fetch("select 1 from change_sequence for update"));
    }

    private interface Unpacked {
        StagingRestore.Outcome restore(Path unpacked, Manifest manifest);
    }

    private StagingRestore.Outcome withUnpacked(Path file, String identity, Unpacked then) {
        Path unpacked;
        try {
            Files.createDirectories(work);
            unpacked = Files.createTempDirectory(work, "restore-");
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        try {
            // Unpacked before anything is replaced: an archive that cannot be read fails
            // while the current state is still whole.
            Manifest manifest = reader.unpack(file, identity, unpacked);
            requireNotNewer(manifest);
            return then.restore(unpacked, manifest);
        } finally {
            deleteTree(unpacked);
        }
    }

    /**
     * Another family's archive is refused on a running server. Restored, it replaced
     * this family -- members, devices, the administrator who started it -- by
     * strangers. That archive belongs on a new instance, through the setup wizard.
     */
    private void requireOwnFamily(Manifest manifest) {
        if (!manifest.familyId().equals(settings.find(SettingKey.FAMILY_ID).orElse(null))) {
            throw HiwiskiException.invalid(
                    "admin.backup_other_family",
                    "familyName",
                    manifest.familyName() == null ? "" : manifest.familyName());
        }
    }

    /** An archive of a newer server is refused with the version it needs. */
    private void requireNotNewer(Manifest manifest) {
        if (SchemaVersion.newer(manifest.schemaVersion(), SchemaVersion.of(db, "public"))) {
            throw HiwiskiException.invalid("admin.backup_too_new", "serverVersion", manifest.serverVersion());
        }
    }

    // --- Backup password -----------------------------------------------------------

    /**
     * Wraps the same key anew -- in the database and in the header of every archive in
     * the directory made with it. Copies already downloaded keep the old password.
     */
    void changePassword(String currentPassword, String newPassword) {
        running.lock();
        try {
            String recipient = keys.require().recipient();
            KeySlot slot = keys.change(currentPassword, newPassword);
            for (BackupArchive archive : directory.list()) {
                if (!archive.header().info().recipient().equals(recipient)) {
                    continue;
                }
                try {
                    ArchiveHeader.writeSpareSlot(archive.file(), archive.header(), slot);
                } catch (IOException e) {
                    // That archive keeps the old password -- the log names it.
                    log.error("backup {} keeps the old backup password: its header could not be written", archive.id(), e);
                }
            }
        } finally {
            running.unlock();
        }
    }

    /**
     * A new key pair: backups from now on use the new password, archives made before
     * open only with the old one.
     */
    void resetPassword(String newPassword) {
        running.lock();
        try {
            keys.create(newPassword);
            if (failure().map(failure -> failure.reason() == FailureReason.NO_BACKUP_PASSWORD).orElse(false)) {
                settings.remove(SettingKey.BACKUP_FAILURE);
            }
        } finally {
            running.unlock();
        }
    }

    // --- Helpers -------------------------------------------------------------------

    String serverVersion() {
        return build != null ? build.getVersion() : "dev";
    }

    static void deleteTree(Path root) {
        if (!Files.exists(root)) {
            return;
        }
        try (var files = Files.walk(root)) {
            for (Path path : files.sorted(Comparator.reverseOrder()).toList()) {
                Files.deleteIfExists(path);
            }
        } catch (IOException e) {
            log.warn("could not remove {}", root, e);
        }
    }

    /** Why a backup failed, in words the settings can say. */
    enum FailureReason {
        DIRECTORY_NOT_WRITABLE,
        DISK_FULL,
        NO_BACKUP_PASSWORD,
        OTHER;

        static FailureReason of(Throwable error) {
            for (Throwable cause = error; cause != null; cause = cause.getCause()) {
                if (cause instanceof HiwiskiException hiwiski && "admin.backup_password_missing".equals(hiwiski.code())) {
                    return NO_BACKUP_PASSWORD;
                }
                String message = String.valueOf(cause.getMessage());
                if (message.contains("No space left") || message.contains("Disk quota")) {
                    return DISK_FULL;
                }
                if (cause instanceof AccessDeniedException
                        || (cause instanceof FileSystemException && message.contains("Read-only"))) {
                    return DIRECTORY_NOT_WRITABLE;
                }
            }
            return OTHER;
        }
    }
}
