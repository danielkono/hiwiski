package de.danielkononov.hiwiski.build

import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.tasks.InputFile
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction
import org.yaml.snakeyaml.Yaml

/**
 * The contract rules (docs/development/api.md), checked rather than promised.
 *
 * `openapi-diff` alone is not enough for that. It judges a change from the *caller's*
 * point of view: removing a field from a response counts as compatible there, because
 * the request is unaffected. Our clients, however, **read** those responses, and a
 * renamed field is a vanished one to them. Exactly this case -- "rename a field" -- is let through by `openapi-diff`.
 *
 * This task therefore additionally checks, literally:
 *
 * * A path, a method or an `operationId` does not disappear.
 * * A schema does not disappear.
 * * A property does not disappear and keeps its type.
 * * `required` is never added after the fact.
 * * Enums are only extended, never shortened.
 *
 * Added paths, schemas, properties and enum values are explicitly allowed -- fields
 * only additive and optional.
 *
 * The comparison is against the most recently **published** baseline. It is moved
 * forward only at release time: a baseline that every build drags along no longer
 * checks anything.
 */
abstract class SpecContractTask : DefaultTask() {

    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val baseline: RegularFileProperty

    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val current: RegularFileProperty

    init {
        group = "verification"
        description = "Fails if the spec breaks the contract -- naming the spot in plain text"
    }

    @TaskAction
    fun check() {
        val yaml = Yaml()
        val old = yaml.load<Map<String, Any?>>(baseline.get().asFile.readText())
        val new = yaml.load<Map<String, Any?>>(current.get().asFile.readText())

        val violations = mutableListOf<String>()
        checkPaths(old, new, violations)
        checkSchemas(old, new, violations)

        if (violations.isNotEmpty()) {
            throw GradleException(
                buildString {
                    appendLine("The spec breaks the contract:")
                    violations.sorted().forEach { appendLine("  - $it") }
                    appendLine()
                    appendLine("Fields only additive and optional. Never rename, never change the")
                    appendLine("meaning, never make required after the fact. Only extend enums.")
                    appendLine()
                    appendLine("If this is a deliberate break, it is called /api/v2 and comes at the")
                    appendLine("turn of the year. If this is a release, ./gradlew :api:acceptSpecBaseline")
                    appendLine("moves the baseline forward.")
                },
            )
        }
    }

    private fun checkPaths(
        old: Map<String, Any?>,
        new: Map<String, Any?>,
        violations: MutableList<String>,
    ) {
        val oldPaths = old.map("paths")
        val newPaths = new.map("paths")

        for ((path, oldItemRaw) in oldPaths) {
            val newItem = newPaths.map(path)
            if (newItem.isEmpty()) {
                violations += "path $path has disappeared"
                continue
            }
            val oldItem = oldItemRaw.asMap()
            for ((method, oldOperation) in oldItem) {
                if (method !in HTTP_METHODS) continue
                val newOperation = newItem.map(method)
                if (newOperation.isEmpty()) {
                    violations += "$method $path has disappeared"
                    continue
                }
                val oldId = oldOperation.asMap()["operationId"]
                val newId = newOperation["operationId"]
                if (oldId != null && oldId != newId) {
                    violations += "$method $path: operationId $oldId is now called $newId"
                }
            }
        }
    }

    private fun checkSchemas(
        old: Map<String, Any?>,
        new: Map<String, Any?>,
        violations: MutableList<String>,
    ) {
        val oldSchemas = old.map("components").map("schemas")
        val newSchemas = new.map("components").map("schemas")

        for ((name, oldSchemaRaw) in oldSchemas) {
            val newSchema = newSchemas.map(name)
            if (newSchema.isEmpty()) {
                violations += "schema $name has disappeared"
                continue
            }
            checkSchema(name, oldSchemaRaw.asMap(), newSchema, violations)
        }
    }

    /**
     * One schema against its earlier self -- and, recursively, its properties, its
     * array elements and inline objects: a changed element type or a property made
     * nullable broke old clients just as much as a changed property type, and passed.
     */
    private fun checkSchema(
        label: String,
        old: Map<String, Any?>,
        new: Map<String, Any?>,
        violations: MutableList<String>,
    ) {
        for (key in listOf("type", "format", "\$ref")) {
            val before = old[key]
            val after = new[key]
            if (before != null && before != after) {
                violations += "$label: $key was $before, is now $after"
            }
        }

        // Only extend enums.
        val removedValues = old.list("enum") - new.list("enum").toSet()
        if (removedValues.isNotEmpty()) {
            violations += "$label: enum values dropped: ${removedValues.joinToString()}"
        }

        // A client with a non-null field fails on decoding a null.
        if (old["nullable"] != true && new["nullable"] == true) {
            violations += "$label: nullable after the fact"
        }

        // `required` is never added after the fact -- nor taken away: a client that
        // relies on the field fails when it is left out.
        val added = new.list("required") - old.list("required").toSet()
        if (added.isNotEmpty()) {
            violations += "$label: required after the fact: ${added.joinToString()}"
        }
        val dropped = old.list("required") - new.list("required").toSet()
        if (dropped.isNotEmpty()) {
            violations += "$label: no longer required: ${dropped.joinToString()}"
        }

        // Properties: stay present and keep their shape.
        val newProperties = new.map("properties")
        for ((property, oldProperty) in old.map("properties")) {
            val newProperty = newProperties.map(property)
            if (newProperty.isEmpty()) {
                violations += "$label.$property has disappeared"
                continue
            }
            checkSchema("$label.$property", oldProperty.asMap(), newProperty, violations)
        }

        // Array elements.
        val oldItems = old.map("items")
        if (oldItems.isNotEmpty()) {
            checkSchema("$label[]", oldItems, new.map("items"), violations)
        }
    }

    private companion object {
        val HTTP_METHODS = setOf("get", "put", "post", "delete", "patch", "head", "options", "trace")

        @Suppress("UNCHECKED_CAST")
        fun Any?.asMap(): Map<String, Any?> = this as? Map<String, Any?> ?: emptyMap()

        fun Map<String, Any?>.map(key: String): Map<String, Any?> = this[key].asMap()

        fun Map<String, Any?>.list(key: String): List<Any?> = this[key] as? List<Any?> ?: emptyList()
    }
}
