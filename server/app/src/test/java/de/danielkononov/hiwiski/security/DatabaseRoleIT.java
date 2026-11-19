package de.danielkononov.hiwiski.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import de.danielkononov.hiwiski.support.PostgresContainer;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.regex.Pattern;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.testcontainers.postgresql.PostgreSQLContainer;

/**
 * The server's database role is no superuser: a statement injected into a query cannot
 * become a shell on the database host.
 *
 * <p>Both SQL texts come from where an operator gets them: the role a new install
 * creates from the init script in deploy/docker-compose.yml, the move of an install from
 * before from the website's update guide (site/content/en/setup/updates.md). If either
 * stops working for the migrations, this fails -- not a family's update.
 */
@Tag("integration")
class DatabaseRoleIT {

    private static final Path REPOSITORY = Path.of("../..").toAbsolutePath().normalize();

    /** A new install: the image's superuser creates the server's role, the server migrates. */
    @Test
    void everyMigrationRunsAsTheServersOwnRole() throws Exception {
        try (var postgres = postgres("postgres")) {
            postgres.start();
            execute(postgres, "postgres", "secret", composeInitSql());

            var result = flyway(postgres, "hiwiski", "hiwiski", "classpath:db/migration").migrate();

            assertThat(result.success).isTrue();
            assertThat(result.migrationsExecuted).isPositive();
            try (var db = connect(postgres, "hiwiski", "hiwiski")) {
                assertThat(superuser(db)).isFalse();
                // What a superuser would turn an injected statement into: a shell.
                assertThatThrownBy(() -> db.createStatement().execute("copy (select 1) to program 'id'"))
                        .isInstanceOf(SQLException.class)
                        .hasMessageContaining("permission denied");
            }
        }
    }

    /**
     * An install from before: the bootstrap superuser built the schema. After the move
     * the new role owns every table and runs a later migration that changes one.
     */
    @Test
    void anInstallFromBeforeMovesToARoleOfItsOwn() throws Exception {
        try (var postgres = postgres("hiwiski")) {
            postgres.start();
            assertThat(flyway(postgres, "hiwiski", "secret", "classpath:db/migration").migrate().success)
                    .isTrue();

            execute(postgres, "hiwiski", "secret", guideMoveSql().replace("NEW-PASSWORD", "moved"));

            try (var db = connect(postgres, "hiwiski_app", "moved")) {
                assertThat(superuser(db)).isFalse();
                var others = db.createStatement()
                        .executeQuery(
                                """
                                select count(*) from pg_class c
                                join pg_namespace n on n.oid = c.relnamespace
                                where n.nspname = 'public' and c.relkind in ('r', 'p', 'S', 'i', 'v', 'm')
                                  and pg_get_userbyid(c.relowner) <> 'hiwiski_app'
                                """);
                others.next();
                assertThat(others.getInt(1)).as("relations not owned by the new role").isZero();
            }
            var later = flyway(postgres, "hiwiski_app", "moved", "classpath:db/migration", "classpath:db/role-probe")
                    .migrate();
            assertThat(later.success).isTrue();
            assertThat(later.migrationsExecuted).isEqualTo(1);
        }
    }

    private static PostgreSQLContainer postgres(String superuser) {
        return new PostgreSQLContainer(PostgresContainer.IMAGE)
                .withDatabaseName("hiwiski")
                .withUsername(superuser)
                .withPassword("secret");
    }

    /** The statements between {@code <<'SQL'} and {@code SQL}, with psql's variables filled in. */
    private static String composeInitSql() throws IOException {
        var compose = Files.readString(REPOSITORY.resolve("deploy/docker-compose.yml"));
        var matcher = Pattern.compile("<<'SQL'\\n(.*?)\\n\\s*SQL\\n", Pattern.DOTALL).matcher(compose);
        assertThat(matcher.find()).as("the init script's SQL in deploy/docker-compose.yml").isTrue();
        return matcher.group(1)
                .replace(":\"role\"", "\"hiwiski\"")
                .replace(":'password'", "'hiwiski'")
                .replace(":\"db\"", "\"hiwiski\"");
    }

    /** The SQL block of the update guide, which an operator pastes into psql as it stands. */
    private static String guideMoveSql() throws IOException {
        var guide = Files.readString(REPOSITORY.resolve("site/content/en/setup/updates.md"));
        var matcher = Pattern.compile("```sql\\n(.*?)\\n\\s*```", Pattern.DOTALL).matcher(guide);
        assertThat(matcher.find()).as("the move's SQL in site/content/en/setup/updates.md").isTrue();
        return matcher.group(1).stripIndent();
    }

    private static Flyway flyway(PostgreSQLContainer postgres, String user, String password, String... locations) {
        return Flyway.configure()
                .dataSource(postgres.getJdbcUrl(), user, password)
                .locations(locations)
                .load();
    }

    private static Connection connect(PostgreSQLContainer postgres, String user, String password)
            throws SQLException {
        return DriverManager.getConnection(postgres.getJdbcUrl(), user, password);
    }

    private static void execute(PostgreSQLContainer postgres, String user, String password, String sql)
            throws SQLException {
        try (var db = connect(postgres, user, password)) {
            db.createStatement().execute(sql);
        }
    }

    private static boolean superuser(Connection db) throws SQLException {
        var result = db.createStatement()
                .executeQuery("select rolsuper from pg_roles where rolname = current_user");
        result.next();
        return result.getBoolean(1);
    }
}
