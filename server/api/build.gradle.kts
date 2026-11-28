plugins {
    id("hiwiski.java-conventions")
    alias(libs.plugins.openapiGenerator)
}

// This project contains no handwritten line. It turns the OpenAPI spec into Spring
// interfaces and DTOs; the controllers in the :app project implement these interfaces
// and so cannot drift from the contract without breaking the build.
val specFile = rootProject.layout.projectDirectory.file("../api/openapi.yaml")
val generatedSources = layout.buildDirectory.dir("generated/openapi/src/main/java")

/**
 * All files the spec consists of.
 *
 * `inputSpec` only knows the root file. If one of the files pulled in via `$ref`
 * changes, the task still counts as up to date -- the build would pass and keep
 * generating the old contract. That is why the tasks depend on the whole directory.
 *
 * Without the bundle: it is output, not source, and as an input of the task that
 * produces it, it would be a cycle.
 */
val specSources = rootProject.layout.projectDirectory.dir("../api").asFileTree.matching {
    include("**/*.yaml")
    exclude("openapi.bundled.yaml")
    exclude("openapi.baseline.yaml")
}

openApiGenerate {
    generatorName = "spring"
    inputSpec = specFile
    outputDir = layout.buildDirectory.dir("generated/openapi")
    apiPackage = "de.danielkononov.hiwiski.api"
    modelPackage = "de.danielkononov.hiwiski.api.model"
    invokerPackage = "de.danielkononov.hiwiski.api.invoker"
    configOptions = mapOf(
        "interfaceOnly" to "true",
        "useSpringBoot3" to "true",
        "useJakartaEe" to "true",
        "documentationProvider" to "none",
        "annotationLibrary" to "none",
        "openApiNullable" to "false",
        "skipDefaultInterface" to "true",
        "useTags" to "true",
        "useOptional" to "false",
        "hideGenerationTimestamp" to "true",
        "unhandledException" to "true",
        // What a field means is in the spec. The inclusion rules belong to the
        // global ObjectMapper, not to every single field.
        "generateJsonIncludeAnnotations" to "false",
        "generateJsonSetterNullsAnnotations" to "false",
    )
    // The generator follows the $ref chains from the root file on its own.
    // `inputSpecRootDirectory` would be wrong here: it merges all YAML files in the
    // directory into one spec.
    validateSpec = true
}

tasks.named("openApiGenerate") {
    inputs.files(specSources).withPropertyName("specSources")
}

sourceSets.named("main") {
    java.srcDir(tasks.named("openApiGenerate").map { generatedSources })
}

dependencies {
    api(platform("org.springframework.boot:spring-boot-dependencies:${libs.versions.springBoot.get()}"))
    api("org.springframework:spring-web")
    api("org.springframework:spring-context")
    api("jakarta.validation:jakarta.validation-api")
    api("jakarta.annotation:jakarta.annotation-api")
    api("com.fasterxml.jackson.core:jackson-annotations")
    compileOnly("jakarta.servlet:jakarta.servlet-api")
    compileOnly(libs.findbugs.jsr305)
}

/**
 * For writing, the spec is split into one file per module; for reading, a single file
 * is better: the Dart generator does not follow file `$ref`s, and `openapi-diff` needs
 * two comparable single files anyway.
 *
 * This task resolves all references and puts the result next to the source. The
 * bundled file is checked in -- it is not code but the published contract.
 */
val bundleSpec = tasks.register<org.openapitools.generator.gradle.plugin.tasks.GenerateTask>("bundleSpec") {
    group = "openapi tools"
    description = "Resolves all references and writes api/openapi.bundled.yaml"
    generatorName = "openapi-yaml"
    inputSpec = specFile
    outputDir = layout.buildDirectory.dir("bundled")
    configOptions = mapOf("outputFile" to "openapi.bundled.yaml")
    generateApiDocumentation = false
    generateModelDocumentation = false
    validateSpec = true
    inputs.files(specSources).withPropertyName("specSources")
}

// Exactly one file as output, not the directory: otherwise this task claims all of
// `api/`, and Gradle sees a dependency on everything that reads from there -- including
// the code generation, which only needs the sources.
val updateBundledSpec = tasks.register("updateBundledSpec") {
    group = "openapi tools"
    description = "Updates the bundled spec in the repository"
    dependsOn(bundleSpec)
    val source = layout.buildDirectory.file("bundled/openapi.bundled.yaml")
    val target = rootProject.layout.projectDirectory.file("../api/openapi.bundled.yaml")
    inputs.file(source)
    outputs.file(target)
    doLast {
        source.get().asFile.copyTo(target.asFile, overwrite = true)
    }
}

/**
 * The barrier against breaking changes to the contract.
 *
 * The comparison is against `api/openapi.baseline.yaml` -- the last **published**
 * state. The baseline is moved forward explicitly (`acceptSpecBaseline`), by
 * tool/release.sh at the start of a release branch and at the release, and not during
 * development: a baseline that every build drags along checks nothing anymore.
 */
val specBaseline = rootProject.layout.projectDirectory.file("../api/openapi.baseline.yaml")

val diffRuntime = configurations.create("diffRuntime")

dependencies {
    diffRuntime(libs.openapi.diff.cli)
}

/**
 * The contract rules, literally: no field disappears, none changes its type,
 * nothing becomes `required` after the fact, enums are only extended.
 *
 * `openapi-diff` alone is not enough for that -- it judges a change from the caller's
 * point of view and lets a renamed response field through. But our clients read those
 * responses, and to them a renamed field is a vanished one.
 */
tasks.register<de.danielkononov.hiwiski.build.SpecContractTask>("checkSpecContract") {
    dependsOn(updateBundledSpec)
    // `acceptSpecBaseline build` at release: check against the baseline just written,
    // not whichever ran first.
    mustRunAfter("acceptSpecBaseline")
    baseline = specBaseline
    current = rootProject.layout.projectDirectory.file("../api/openapi.bundled.yaml")
    onlyIf { specBaseline.asFile.exists() }
}

tasks.register<JavaExec>("checkSpecCompatibility") {
    group = "verification"
    description = "Fails when the spec breaks the contract"
    dependsOn(updateBundledSpec)
    mustRunAfter("acceptSpecBaseline")
    classpath = diffRuntime
    mainClass = "org.openapitools.openapidiff.cli.Main"
    args(
        specBaseline.asFile.absolutePath,
        rootProject.layout.projectDirectory.file("../api/openapi.bundled.yaml").asFile.absolutePath,
        // Fails as soon as a change would lock out old clients.
        // Added fields and endpoints are explicitly allowed.
        "--fail-on-incompatible",
    )
    onlyIf {
        // Before the first release there is no baseline yet. Then there is nothing to
        // check -- and a build that fails on it would not have helped anyone.
        specBaseline.asFile.exists()
    }
}

// Hooked onto `check` so it runs on every build and not only when someone remembers
// to.
tasks.named("check") {
    dependsOn("checkSpecCompatibility", "checkSpecContract")
}

tasks.register("acceptSpecBaseline") {
    group = "openapi tools"
    description = "Sets the baseline to the current state -- at release time"
    dependsOn(updateBundledSpec)
    val source = rootProject.layout.projectDirectory.file("../api/openapi.bundled.yaml")
    val target = specBaseline
    inputs.file(source)
    outputs.file(target)
    doLast {
        source.asFile.copyTo(target.asFile, overwrite = true)
    }
}

// This project contains no handwritten line. Lint warnings from it are reports about
// the generator, not about us -- they would bury the warnings that matter.
tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.removeIf { it.startsWith("-Xlint") }
    options.compilerArgs.add("-Xlint:none")
    options.isWarnings = false
}
