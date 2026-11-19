plugins {
    alias(libs.plugins.springBoot) apply false
    alias(libs.plugins.openapiGenerator) apply false
    alias(libs.plugins.jib) apply false
}

allprojects {
    group = "de.danielkononov"
    version = providers.gradleProperty("hiwiski.version").getOrElse("0.0.0-SNAPSHOT")
}
