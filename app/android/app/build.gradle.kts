import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // The home screen widgets (docs/development/home-widgets.md).
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("org.openapi.generator")
}

// The release key, from `android/key.properties` (git-ignored): storeFile, storePassword,
// keyAlias, keyPassword. Signed with the debug key, a release built on another machine --
// or after the debug keystore was regenerated -- could not update the installed app:
// only uninstalling helped, and that wipes the database and the outbox.
val releaseKey = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

// The home screen widgets ask the server themselves while the app is closed — only
// native code runs then. Their client is generated from the contract, like the Dart
// client and the server's interfaces, and never checked in: only the two reads they make
// (getAgenda, getListSummary) and the types those answer with. The bundled spec, because
// it is one file; it is refreshed with `./gradlew :api:updateBundledSpec` in server/.
val widgetApi = layout.buildDirectory.dir("generated/widget-api")

openApiGenerate {
    generatorName = "kotlin"
    inputSpec = rootProject.layout.projectDirectory.file("../../api/openapi.bundled.yaml")
    outputDir = widgetApi
    packageName = "de.danielkononov.hiwiski.widgets.api"
    library = "jvm-okhttp4"
    configOptions = mapOf(
        "serializationLibrary" to "kotlinx_serialization",
        "dateLibrary" to "java8",
        // The widgets' schemas carry no enums (a generated Kotlin enum throws on a value
        // it does not know); should one come in anyway, it falls back instead.
        "enumUnknownDefaultCase" to "true",
        "omitGradleWrapper" to "true",
    )
    // Everything else in the contract is left out: the widgets make these two calls.
    openapiNormalizer = mapOf("FILTER" to "operationId:getAgenda|getListSummary")
    apiFilesConstrainedTo = listOf("Calendar", "Todo")
    modelFilesConstrainedTo = listOf(
        "Agenda",
        "AgendaOccurrence",
        "ListSummary",
        "ListSummaryColumn",
        "ListSummaryItem",
        // Named in the calls' error answers.
        "ApiError",
    )
    // Naming the APIs and models switches every other file off; the client's own
    // infrastructure is named here, the generator's build files are not.
    supportingFilesConstrainedTo = listOf(
        "ApiAbstractions.kt",
        "ApiClient.kt",
        "ApiResponse.kt",
        "AtomicBooleanAdapter.kt",
        "AtomicIntegerAdapter.kt",
        "AtomicLongAdapter.kt",
        "BigDecimalAdapter.kt",
        "BigIntegerAdapter.kt",
        "Errors.kt",
        "LocalDateAdapter.kt",
        "LocalDateTimeAdapter.kt",
        "OffsetDateTimeAdapter.kt",
        "PartConfig.kt",
        "RequestConfig.kt",
        "RequestMethod.kt",
        "ResponseExtensions.kt",
        "Serializer.kt",
        "StringBuilderAdapter.kt",
        "URIAdapter.kt",
        "URLAdapter.kt",
        "UUIDAdapter.kt",
    )
    generateApiTests = false
    generateModelTests = false
    generateApiDocumentation = false
    generateModelDocumentation = false
}

tasks.named("preBuild") { dependsOn("openApiGenerate") }

// Every library the app ships has its license on its licenses page
// (docs/development/app.md, "Licenses"). Flutter lists the Dart packages and its own
// engine (`io.flutter`) by itself; the native libraries -- the widgets', the plugins'
// own -- come from assets/licenses/native.json. One that no entry there covers stops
// the build, so that a new library cannot ship without its license.
val checkNativeLicenses by tasks.registering {
    val manifest = rootProject.layout.projectDirectory.file("../assets/licenses/native.json")
    inputs.file(manifest)
    // What goes into the APK. Not `coreLibraryDesugaring`: at this minSdk none of it
    // does, which the check after `l8DexDesugarLibRelease` below holds.
    val roots = listOf("releaseRuntimeClasspath").map {
        configurations.getByName(it).incoming.resolutionResult.rootComponent
    }
    doLast {
        @Suppress("UNCHECKED_CAST")
        val libraries = (groovy.json.JsonSlurper().parse(manifest.asFile) as Map<String, Any>)["libraries"]
            as List<Map<String, Any>>
        val covers = libraries
            .filter { "android" in (it["platforms"] as List<*>) }
            .flatMap { it["covers"] as List<*> }
            .map { it as String }
        fun covered(id: String) =
            covers.any { it == id || ((it.endsWith(".") || it.endsWith(":")) && id.startsWith(it)) }

        val shipped = mutableSetOf<String>()
        for (root in roots) {
            val seen = mutableSetOf<org.gradle.api.artifacts.result.ResolvedComponentResult>()
            val queue = ArrayDeque(listOf(root.get()))
            while (queue.isNotEmpty()) {
                val component = queue.removeFirst()
                if (!seen.add(component)) continue
                (component.id as? org.gradle.api.artifacts.component.ModuleComponentIdentifier)
                    ?.let { shipped += "${it.group}:${it.module}" }
                component.dependencies
                    .filterIsInstance<org.gradle.api.artifacts.result.ResolvedDependencyResult>()
                    .forEach { queue += it.selected }
            }
        }
        val missing = shipped.filterNot { it.startsWith("io.flutter:") || covered(it) }.sorted()
        if (missing.isNotEmpty()) {
            throw GradleException(
                "No license on the licenses page for ${missing.joinToString()}: add an entry " +
                    "to app/assets/licenses/native.json (docs/development/app.md, \"Licenses\").",
            )
        }
    }
}

tasks.named("preBuild") { dependsOn(checkNativeLicenses) }

// Nothing of desugar_jdk_libs goes into a release: it is OpenJDK's class library under
// the GPL (with the Classpath Exception), and at minSdk 26 the app needs none of it --
// java.time is Android's own from 8 on -- so R8 leaves its dex empty. Should a release
// take some of it after all (a lower minSdk, a library calling a newer Java API), the
// build stops here rather than ship GPL code its licenses page does not name.
tasks.matching { it.name == "l8DexDesugarLibRelease" }.configureEach {
    doLast {
        val dex = outputs.files.asFileTree.matching { include("**/*.dex") }.files
        if (dex.isNotEmpty()) {
            throw GradleException(
                "The release takes desugar_jdk_libs (GPL) along: ${dex.joinToString()}. " +
                    "Find what calls a Java API Android lacks at minSdk, or list it in " +
                    "app/assets/licenses/native.json (docs/development/app.md, \"Licenses\").",
            )
        }
    }
}

android {
    namespace = "de.danielkononov.hiwiski"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications asks for desugaring in its AAR metadata, and the
        // build refuses to go on without it -- at minSdk 26 it adds nothing (see the
        // check after `l8DexDesugarLibRelease`).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "de.danielkononov.hiwiski"
        // Android 8. Below it java.time is missing, and desugaring would put OpenJDK's
        // class library, GPL code, into the app; devices older than that are a vanishing
        // few.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (!releaseKey.isEmpty) {
            create("release") {
                storeFile = rootProject.file(releaseKey.getProperty("storeFile"))
                storePassword = releaseKey.getProperty("storePassword")
                keyAlias = releaseKey.getProperty("keyAlias")
                keyPassword = releaseKey.getProperty("keyPassword")
            }
        }
    }

    buildFeatures {
        compose = true
    }

    sourceSets {
        getByName("main") {
            // A directory, not a provider: the old source set API takes no provider, and
            // the generation runs before every build (preBuild below).
            java.srcDir(widgetApi.get().dir("src/main/kotlin").asFile)
        }
    }

    buildTypes {
        release {
            // The app's own rules on top of the ones Flutter applies: what R8 must not
            // merge or remove is said there, next to its reason.
            proguardFiles("proguard-rules.pro")
            signingConfig = if (releaseKey.isEmpty) {
                // Without the key a release still builds -- `flutter run --release` --
                // but it is not one to hand out.
                logger.warn("android/key.properties is missing: release signed with the debug key")
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // The home screen widgets: Glance draws them, WorkManager refreshes them while the
    // app is closed, and the generated client asks the server with OkHttp.
    implementation("androidx.glance:glance-appwidget:1.2.0")
    implementation("androidx.glance:glance-material3:1.2.0")
    implementation("androidx.work:work-runtime-ktx:2.11.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    testImplementation("junit:junit:4.13.2")
}
