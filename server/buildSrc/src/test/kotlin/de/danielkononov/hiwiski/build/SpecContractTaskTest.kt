package de.danielkononov.hiwiski.build

import java.io.File
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertFailsWith
import org.gradle.api.GradleException
import org.gradle.testfixtures.ProjectBuilder
import org.junit.jupiter.api.io.TempDir

/**
 * The contract rules, played through on a miniature contract.
 *
 * The gate runs without a baseline until the first release and therefore not in the normal build.
 * Without this test it would go unused until the release -- and unused code is untested
 * code.
 */
class SpecContractTaskTest {

    @TempDir
    lateinit var dir: File

    private fun check(baseline: String, current: String) {
        val baselineFile = File(dir, "baseline.yaml").apply { writeText(baseline) }
        val currentFile = File(dir, "current.yaml").apply { writeText(current) }

        val project = ProjectBuilder.builder().withProjectDir(dir).build()
        val task = project.tasks.register("checkContract", SpecContractTask::class.java).get()
        task.baseline.set(baselineFile)
        task.current.set(currentFile)
        task.check()
    }

    private val base = """
        paths:
          /api/v1/handshake:
            get:
              operationId: getHandshake
        components:
          schemas:
            Handshake:
              type: object
              required: [apiVersion]
              properties:
                apiVersion:
                  type: string
                familyName:
                  type: string
                groupIds:
                  type: array
                  items:
                    type: string
                    format: uuid
            ColorToken:
              type: string
              enum: [BLUE, RUST]
    """.trimIndent()

    @Test
    fun `an added optional field is allowed`() {
        check(base, base.replace("        familyName:", "        probeField:\n          type: string\n        familyName:"))
    }

    @Test
    fun `an extended enum is allowed`() {
        check(base, base.replace("enum: [BLUE, RUST]", "enum: [BLUE, RUST, TEAL]"))
    }

    @Test
    fun `a renamed field fails -- exactly the case openapi-diff lets through`() {
        val failure = assertFailsWith<GradleException> {
            check(base, base.replace("familyName:", "familyNameRenamed:"))
        }
        assertContains(failure.message!!, "Handshake.familyName has disappeared")
    }

    @Test
    fun `a changed type fails`() {
        val failure = assertFailsWith<GradleException> {
            check(base, base.replace("        apiVersion:\n          type: string", "        apiVersion:\n          type: integer"))
        }
        assertContains(failure.message!!, "type was string, is now integer")
    }

    @Test
    fun `required after the fact fails`() {
        val failure = assertFailsWith<GradleException> {
            check(base, base.replace("required: [apiVersion]", "required: [apiVersion, familyName]"))
        }
        assertContains(failure.message!!, "required after the fact: familyName")
    }

    @Test
    fun `nullable after the fact fails`() {
        val failure = assertFailsWith<GradleException> {
            check(base, base.replace("        apiVersion:\n          type: string", "        apiVersion:\n          type: string\n          nullable: true"))
        }
        assertContains(failure.message!!, "Handshake.apiVersion: nullable after the fact")
    }

    @Test
    fun `a field no longer required fails`() {
        val failure = assertFailsWith<GradleException> {
            check(base, base.replace("required: [apiVersion]", "required: []"))
        }
        assertContains(failure.message!!, "no longer required: apiVersion")
    }

    @Test
    fun `a changed element type fails`() {
        val failure = assertFailsWith<GradleException> {
            check(base, base.replace("          type: string\n            format: uuid", "          type: integer"))
        }
        assertContains(failure.message!!, "Handshake.groupIds[]: type was string, is now integer")
    }

    @Test
    fun `a shortened enum fails`() {
        val failure = assertFailsWith<GradleException> {
            check(base, base.replace("enum: [BLUE, RUST]", "enum: [BLUE]"))
        }
        assertContains(failure.message!!, "enum values dropped: RUST")
    }

    @Test
    fun `a vanished path fails`() {
        val failure = assertFailsWith<GradleException> {
            check(base, base.replace("  /api/v1/handshake:\n    get:\n      operationId: getHandshake\n", ""))
        }
        assertContains(failure.message!!, "path /api/v1/handshake has disappeared")
    }

    @Test
    fun `a renamed operationId fails`() {
        val failure = assertFailsWith<GradleException> {
            check(base, base.replace("operationId: getHandshake", "operationId: handshake"))
        }
        assertContains(failure.message!!, "operationId getHandshake is now called handshake")
    }
}
