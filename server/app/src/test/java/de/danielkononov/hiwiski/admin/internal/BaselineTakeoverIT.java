package de.danielkononov.hiwiski.admin.internal;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.PostgresContainer;
import java.sql.DriverManager;
import java.sql.SQLException;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.testcontainers.postgresql.PostgreSQLContainer;

/**
 * A database from 2026.1.8 or 2026.1.9 -- its history 1 to 36, the last with the old
 * checksum -- starts on the baseline without anything being run, and validation still
 * stops what it is there for.
 */
@Tag("integration")
class BaselineTakeoverIT {

    @Test
    void aSchemaFromBeforeTheBaselineIsTakenOver() throws Exception {
        try (var postgres = postgres()) {
            postgres.start();
            var flyway = flyway(postgres);
            flyway.migrate();
            asBeforeTheBaseline(postgres);
            assertThat(flyway.validateWithResult().validationSuccessful).isFalse();

            BaselineTakeover.apply(flyway);

            assertThat(flyway.validateWithResult().validationSuccessful).isTrue();
            assertThat(flyway.migrate().migrationsExecuted).isZero();
        }
    }

    /**
     * Only a history from before the baseline is repaired: an edited baseline on a
     * database that ran it is a mistake, and validation still stops the start.
     */
    @Test
    void anEditedBaselineStillStopsTheStart() throws Exception {
        try (var postgres = postgres()) {
            postgres.start();
            var flyway = flyway(postgres);
            flyway.migrate();
            execute(postgres, "update flyway_schema_history set checksum = 1 where version = '036'");

            BaselineTakeover.apply(flyway);

            assertThat(flyway.validateWithResult().validationSuccessful).isFalse();
        }
    }

    /** What the history of a server that ran migrations 1 to 36 one by one looks like. */
    private static void asBeforeTheBaseline(PostgreSQLContainer postgres) throws SQLException {
        execute(postgres, """
                update flyway_schema_history
                set installed_rank = 36, description = 'invitation code slow hash',
                    script = 'V036__invitation_code_slow_hash.sql', checksum = 123456
                where version = '036';
                insert into flyway_schema_history
                    (installed_rank, version, description, type, script, checksum, installed_by, execution_time, success)
                select n, lpad(n::text, 3, '0'), 'step ' || n, 'SQL', 'V' || lpad(n::text, 3, '0') || '__step.sql', n, 'hiwiski', 0, true
                from generate_series(1, 35) as n;
                """);
    }

    private static PostgreSQLContainer postgres() {
        return new PostgreSQLContainer(PostgresContainer.IMAGE)
                .withDatabaseName("hiwiski")
                .withUsername("hiwiski")
                .withPassword("secret");
    }

    private static Flyway flyway(PostgreSQLContainer postgres) {
        return Flyway.configure()
                .dataSource(postgres.getJdbcUrl(), "hiwiski", "secret")
                .locations("classpath:db/migration")
                .load();
    }

    private static void execute(PostgreSQLContainer postgres, String sql) throws SQLException {
        try (var db = DriverManager.getConnection(postgres.getJdbcUrl(), "hiwiski", "secret")) {
            db.createStatement().execute(sql);
        }
    }
}
