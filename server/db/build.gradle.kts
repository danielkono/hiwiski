import de.danielkononov.hiwiski.build.JooqCodegenTask

plugins {
    id("hiwiski.java-conventions")
}

// This project holds the Flyway migrations and the jOOQ code generated from them. The
// two belong together: the migrations are the source, the generated code the mirror.
// Because :app depends on this project, the migrations are on the classpath at runtime
// and Flyway finds them at startup.
val generateJooq = tasks.register<JooqCodegenTask>("generateJooq") {
    migrationDirectory = layout.projectDirectory.dir("src/main/resources/db/migration")
    outputDirectory = layout.buildDirectory.dir("generated/jooq")
    packageName = "de.danielkononov.hiwiski.db.generated"
}

sourceSets.named("main") {
    java.srcDir(generateJooq.flatMap { it.outputDirectory })
}

dependencies {
    api(platform("org.springframework.boot:spring-boot-dependencies:${libs.versions.springBoot.get()}"))
    api(libs.jooq)
    runtimeOnly(libs.flyway.core)
    runtimeOnly(libs.flyway.postgresql)
}
