package de.danielkononov.hiwiski.admin.internal;

import java.util.Arrays;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationInfo;
import org.flywaydb.core.api.MigrationState;
import org.flywaydb.core.api.MigrationVersion;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * A database built by the migrations before the baseline is taken over by it.
 *
 * <p>Migrations 1 to 36 became one, {@code V036__baseline.sql}. A database from 2026.1.8
 * or 2026.1.9 has the same schema, but its history lists 1 to 35 as well, which no longer
 * exist, and 36 with another checksum: Flyway's validation would stop the server. Its
 * repair marks the missing ones deleted and takes the baseline's checksum -- nothing is
 * run, and the schema stays as it is.
 *
 * <p>Only those: a migration missing from 36 on is a mistake that validation is there
 * to catch, and it still does.
 */
final class BaselineTakeover {

    static final MigrationVersion BASELINE = MigrationVersion.fromVersion("36");

    private static final Logger log = LoggerFactory.getLogger(BaselineTakeover.class);

    private BaselineTakeover() {}

    static void apply(Flyway flyway) {
        MigrationInfo[] missing = Arrays.stream(flyway.info().applied())
                .filter(migration -> migration.getState() == MigrationState.MISSING_SUCCESS)
                .toArray(MigrationInfo[]::new);
        if (missing.length == 0) {
            return;
        }
        boolean beforeBaseline = Arrays.stream(missing)
                .allMatch(migration -> migration.getVersion() != null && migration.getVersion().compareTo(BASELINE) < 0);
        if (!beforeBaseline) {
            return;
        }
        log.warn("Taking the schema over by the baseline: {} migrations before it are marked deleted.", missing.length);
        flyway.repair();
    }
}
