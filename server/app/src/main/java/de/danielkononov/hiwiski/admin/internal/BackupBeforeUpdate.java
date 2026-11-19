package de.danielkononov.hiwiski.admin.internal;

import de.danielkononov.hiwiski.platform.SettingKey;
import de.danielkononov.hiwiski.platform.StartRefused;
import java.io.IOException;
import java.nio.file.Path;
import java.util.Base64;
import java.util.Objects;
import javax.sql.DataSource;
import org.jooq.DSLContext;
import org.jooq.SQLDialect;
import org.jooq.impl.DSL;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.flyway.autoconfigure.FlywayMigrationStrategy;
import org.springframework.boot.info.BuildProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.jspecify.annotations.Nullable;
import tools.jackson.databind.ObjectMapper;

/**
 * <strong>An automatic backup before the migration</strong> -- the administrator does
 * nothing before an update.
 *
 * <p>The server keeps the version it last ran ({@code server.lastVersion}). When it
 * starts with another one on an instance that is set up, it backs up first and migrates
 * after. Any version change, not only one with migrations: new code without a schema
 * change can still damage data.
 *
 * <p><strong>At that moment the code is new and the schema old.</strong> Nothing here
 * goes through the generated jOOQ classes or the application's beans -- they are not
 * there yet, and they describe the new schema. The tables come from the catalog, the
 * settings and the backup's public key from plain SQL, on a {@link DSLContext} of its
 * own.
 *
 * <p><strong>If the backup fails, nothing is migrated</strong> and the server does not
 * start. The old image still starts on the untouched schema -- that is the rollback.
 */
@Configuration(proxyBeanMethods = false)
class BackupBeforeUpdate {

    private static final Logger log = LoggerFactory.getLogger(BackupBeforeUpdate.class);

    @Bean
    FlywayMigrationStrategy backUpBeforeMigrating(
            DataSource dataSource,
            ObjectMapper json,
            ObjectProvider<BuildProperties> build,
            @Value("${hiwiski.backup-path}") String backupPath,
            @Value("${hiwiski.media-path}") String mediaPath) {
        String version = build.getIfAvailable() == null ? "dev" : build.getIfAvailable().getVersion();
        return flyway -> {
            DSLContext db = DSL.using(dataSource, SQLDialect.POSTGRES);
            backUpIfUpdated(db, json, Path.of(backupPath), Path.of(mediaPath), version);
            BaselineTakeover.apply(flyway);
            flyway.migrate();
            remember(db, version);
        };
    }

    /**
     * Backs up if the instance last ran another version. Public to the package for the
     * test, which cannot start a server of another version.
     */
    static void backUpIfUpdated(DSLContext db, ObjectMapper json, Path backupPath, Path mediaPath, String version) {
        if (!hasSettings(db) || !"true".equals(setting(db, SettingKey.SETUP_COMPLETED))) {
            return;
        }
        String last = setting(db, SettingKey.SERVER_LAST_VERSION);
        if (last == null || Objects.equals(last, version)) {
            return;
        }
        String recipient = setting(db, SettingKey.BACKUP_KEY_RECIPIENT);
        var slot = KeySlot.fromBytes(decode(setting(db, SettingKey.BACKUP_KEY_SLOT)));
        if (recipient == null || slot.isEmpty()) {
            log.warn("No backup before the update to {}: no backup password is set. Set one in the settings.", version);
            return;
        }
        log.warn("Backing up before the update to {} -- this can take a few minutes.", version);
        try {
            var directory = new BackupDirectory(backupPath, json);
            new BackupWriter(json, mediaPath)
                    .write(db, directory, BackupReason.BEFORE_UPDATE, last, version, recipient, slot.get());
            directory.prune(keep(db));
        } catch (IOException | RuntimeException e) {
            throw new StartRefused(
                    "The backup before the update to " + version + " failed; nothing was migrated: " + e.getMessage(),
                    "Fix the cause (a full disk, mostly) and start again -- or start the previous version, whose "
                            + "schema is untouched.",
                    e);
        }
    }

    private static void remember(DSLContext db, String version) {
        db.execute(
                "insert into instance_setting (key, value) values (?, ?) "
                        + "on conflict (key) do update set value = excluded.value, updated_at = now()",
                SettingKey.SERVER_LAST_VERSION,
                version);
    }

    private static boolean hasSettings(DSLContext db) {
        return Boolean.TRUE.equals(db.resultQuery("select to_regclass('public.instance_setting') is not null")
                .fetchOne(0, Boolean.class));
    }

    private static @Nullable String setting(DSLContext db, String key) {
        return db.resultQuery("select value from instance_setting where key = ?", key).fetchOne(0, String.class);
    }

    private static int keep(DSLContext db) {
        try {
            String keep = setting(db, SettingKey.BACKUP_KEEP);
            return keep == null ? BackupSchedule.KEEP_DEFAULT : Math.clamp(Integer.parseInt(keep), 1, BackupSchedule.KEEP_MAX);
        } catch (NumberFormatException e) {
            return BackupSchedule.KEEP_DEFAULT;
        }
    }

    private static byte[] decode(@Nullable String slot) {
        return slot == null ? new byte[0] : Base64.getDecoder().decode(slot);
    }
}
