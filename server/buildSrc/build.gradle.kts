plugins {
    `kotlin-dsl`
}

dependencies {
    // The code generator runs in the Gradle process: Testcontainers starts Postgres,
    // Flyway applies the migrations, jOOQ reads the result.
    implementation(libs.jooq.codegen)
    implementation(libs.flyway.core)
    implementation(libs.flyway.postgresql)
    implementation(libs.postgresql)
    implementation(libs.testcontainers.postgresql)

    // The contract gate reads both spec versions structurally.
    implementation(libs.snakeyaml)

    testImplementation(kotlin("test"))
}

kotlin {
    jvmToolchain(libs.versions.java.get().toInt())
}

tasks.test {
    useJUnitPlatform()
}
