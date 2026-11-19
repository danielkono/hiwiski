package de.danielkononov.hiwiski.build

import org.flywaydb.core.Flyway
import org.gradle.api.DefaultTask
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.CacheableTask
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputDirectory
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction
import org.jooq.codegen.GenerationTool
import org.jooq.meta.jaxb.Configuration
import org.jooq.meta.jaxb.Database
import org.jooq.meta.jaxb.Generate
import org.jooq.meta.jaxb.Generator
import org.jooq.meta.jaxb.Jdbc
import org.jooq.meta.jaxb.Target
import org.testcontainers.postgresql.PostgreSQLContainer

/**
 * Generates the jOOQ table classes from the Flyway migrations.
 *
 * The route deliberately goes through a real Postgres in a container and not through
 * an SQL parser: only that way is the generated code guaranteed to mirror what the
 * database will actually contain -- including generated columns, domains and everything
 * else a parser only approximately understands.
 *
 * The task can be up to date via its input and output directories. As long as no
 * migration changes, nothing runs here, and the build does not need Docker.
 */
@CacheableTask
abstract class JooqCodegenTask : DefaultTask() {

    @get:InputDirectory
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val migrationDirectory: DirectoryProperty

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @get:Input
    abstract val packageName: Property<String>

    @get:Input
    abstract val postgresImage: Property<String>

    init {
        group = "build"
        description = "Generates jOOQ classes from the Flyway migrations against a Postgres in a container"
        packageName.convention("de.danielkononov.hiwiski.db.generated")
        postgresImage.convention("postgres:18-alpine")
    }

    @TaskAction
    fun generate() {
        val migrations = migrationDirectory.get().asFile
        val output = outputDirectory.get().asFile
        output.deleteRecursively()
        output.mkdirs()

        PostgreSQLContainer(postgresImage.get())
            .withDatabaseName("hiwiski_codegen")
            .withUsername("hiwiski")
            .withPassword("hiwiski")
            .use { postgres ->
                postgres.start()

                Flyway.configure()
                    .dataSource(postgres.jdbcUrl, postgres.username, postgres.password)
                    .locations("filesystem:${migrations.absolutePath}")
                    .load()
                    .migrate()

                GenerationTool.generate(
                    Configuration()
                        .withJdbc(
                            Jdbc()
                                .withDriver("org.postgresql.Driver")
                                .withUrl(postgres.jdbcUrl)
                                .withUser(postgres.username)
                                .withPassword(postgres.password),
                        )
                        .withGenerator(
                            Generator()
                                .withName("org.jooq.codegen.JavaGenerator")
                                .withDatabase(
                                    Database()
                                        .withName("org.jooq.meta.postgres.PostgresDatabase")
                                        .withInputSchema("public")
                                        .withIncludes(".*")
                                        .withExcludes("flyway_schema_history"),
                                )
                                .withGenerate(
                                    Generate()
                                        .withDeprecated(false)
                                        .withRecords(true)
                                        .withPojos(false)
                                        .withDaos(false)
                                        .withJavaTimeTypes(true)
                                        .withFluentSetters(true)
                                        .withGeneratedAnnotation(false),
                                )
                                .withTarget(
                                    Target()
                                        .withPackageName(packageName.get())
                                        .withDirectory(output.absolutePath)
                                        .withClean(true),
                                ),
                        ),
                )
            }
    }
}
