import org.gradle.api.artifacts.VersionCatalogsExtension

plugins {
    // java-library, because :api and :db pass their generated types on to :app.
    `java-library`
}

// The Java version lives in the version catalog so that it is maintained in one place only.
val javaVersion = the<VersionCatalogsExtension>()
    .named("libs")
    .findVersion("java")
    .orElseThrow()
    .requiredVersion
    .toInt()

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(javaVersion)
    }
}

tasks.withType<JavaCompile>().configureEach {
    options.encoding = "UTF-8"
    // Spring needs -parameters to bind method parameters.
    options.compilerArgs.addAll(listOf("-parameters", "-Xlint:all", "-Xlint:-processing"))
}

tasks.withType<Test>().configureEach {
    useJUnitPlatform()
    testLogging {
        events("failed")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}
