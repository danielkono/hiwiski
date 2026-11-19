import java.security.MessageDigest

plugins {
    id("hiwiski.java-conventions")
    alias(libs.plugins.springBoot)
    alias(libs.plugins.jib)
}

dependencies {
    implementation(platform("org.springframework.boot:spring-boot-dependencies:${libs.versions.springBoot.get()}"))
    implementation(platform(libs.spring.modulith.bom))

    implementation(project(":api"))
    implementation(project(":db"))

    // Boot 4 ships modular starters; spring-boot-starter-web no longer exists as such.
    implementation("org.springframework.boot:spring-boot-starter-webmvc")
    implementation("org.springframework.boot:spring-boot-starter-security")
    implementation("org.springframework.boot:spring-boot-starter-validation")
    implementation("org.springframework.boot:spring-boot-starter-jooq")
    implementation("org.springframework.boot:spring-boot-starter-actuator")

    implementation(libs.spring.modulith.starter.core)
    // Persistent events survive a restart. The search index and the SSE signal need
    // them so that a crash does not swallow a follow-up.
    implementation(libs.spring.modulith.starter.jdbc)

    // Recurrence and ICS. Two libraries for two jobs: lib-recur expands rules, ical4j
    // reads foreign files. ICS is written by hand.
    implementation(libs.lib.recur)
    implementation(libs.ical4j)

    implementation(libs.bucket4j)
    // In Spring Security, Argon2id comes from BouncyCastle.
    implementation(libs.bouncycastle)
    // Reads WebP for its preview: avatars and thumbnails are then a capped JPEG
    // everywhere, never a WebP original of any size.
    implementation(libs.twelvemonkeys.webp)
    // Every backup is an age file to an X25519 recipient.
    implementation(libs.jagged.x25519)

    // Boot 4 splits the auto-configurations into their own modules. Without this one,
    // Flyway would sit on the classpath but never run -- the migrations would silently
    // not run, and that only shows up in production.
    //
    // At compile time too: the backup before an update hooks in before the migration
    // (FlywayMigrationStrategy), and a restore migrates a staging schema of its own.
    implementation("org.springframework.boot:spring-boot-flyway")
    implementation(libs.flyway.core)
    runtimeOnly(libs.postgresql)

    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testImplementation("org.springframework.boot:spring-boot-testcontainers")
    testImplementation("org.springframework.security:spring-security-test")
    testImplementation(libs.spring.modulith.test)
    // Generates an overview from the verified module boundaries under
    // build/spring-modulith-docs.
    testImplementation(libs.spring.modulith.docs)
    testImplementation(platform(libs.testcontainers.bom))
    testImplementation(libs.testcontainers.postgresql)
    testImplementation(libs.testcontainers.junit)
    // DatabaseRoleIT runs the migrations as a role without superuser, outside Spring.
    testImplementation(libs.flyway.core)
}

springBoot {
    buildInfo()
}

// The Flutter web build goes into the server image. Web app and dashboard address thus
// always match the server version exactly -- the server serves exactly the UI it
// belongs to, and the handshake cannot be off there at all.
//
// The web build is built outside of Gradle (the pipeline calls `flutter build web`). If
// the result is not there, the directory stays empty and the application runs anyway --
// it just has no web UI then.
val webBuildDirectory = rootProject.layout.projectDirectory.dir("../app/build/web")

// The web client compares this file with what it was loaded as and offers "Reload" when
// the server now serves another build. The id is a hash of the
// compiled app: the same build keeps its id, every other build gets a new one.
val webBuildId = tasks.register("webBuildId") {
    val app = webBuildDirectory.file("main.dart.js").asFile
    val output = layout.buildDirectory.file("generated/web-build/build.json").get().asFile
    inputs.files(app).withPropertyName("app")
    outputs.file(output)
    doLast {
        output.delete()
        if (!app.exists()) return@doLast
        val id = MessageDigest.getInstance("SHA-256")
            .digest(app.readBytes())
            .joinToString("") { byte -> "%02x".format(byte) }
            .take(16)
        output.parentFile.mkdirs()
        output.writeText("{\"build\":\"$id\"}\n")
    }
}

tasks.named<ProcessResources>("processResources") {
    from(webBuildDirectory) {
        into("static")
    }
    from(webBuildId) {
        into("static")
    }
}

// Container image for amd64 and arm64, so that the app runs on a Raspberry Pi just as it
// does on a NAS. Version tags, no `latest`.
jib {
    from {
        // The exact JDK release, not the moving `25-jre`: two builds of the same tag
        // get the same Java. The tag is still rebuilt for the OS's fixes; a new JDK
        // release is a change here.
        image = "eclipse-temurin:25.0.5_8-jre"
        platforms {
            platform {
                architecture = "amd64"
                os = "linux"
            }
            platform {
                architecture = "arm64"
                os = "linux"
            }
        }
    }
    to {
        image = providers.gradleProperty("hiwiski.image").getOrElse("ghcr.io/danielkono/hiwiski")
        tags = setOf(version.toString())
    }
    // Puts the maintenance command `hiwiski` into the image.
    extraDirectories {
        paths {
            path {
                setFrom(rootProject.layout.projectDirectory.dir("../deploy/image"))
            }
        }
        permissions = mapOf("/usr/local/bin/hiwiski" to "755")
    }
    container {
        ports = listOf("8080")
        jvmFlags = listOf("-XX:MaxRAMPercentage=75")
        user = "1000:1000"
        creationTime = "USE_CURRENT_TIMESTAMP"
        // The source label links the package on ghcr.io to the repository: the package
        // takes over the repository's visibility and access, and the release workflow
        // may push it with the repository's own token.
        // Title and description would otherwise be the base image's ("ubuntu").
        labels = mapOf(
            "org.opencontainers.image.title" to "hiwiski",
            "org.opencontainers.image.description" to "Hiwiski server with the web app",
            "org.opencontainers.image.source" to "https://github.com/danielkono/hiwiski",
            "org.opencontainers.image.version" to version.toString(),
            "org.opencontainers.image.revision" to providers.gradleProperty("hiwiski.revision").getOrElse(""),
        )
    }
}
