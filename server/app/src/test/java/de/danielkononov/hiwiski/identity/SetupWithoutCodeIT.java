package de.danielkononov.hiwiski.identity;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * The default: a family on its home network sets up without the code from the
 * server's log. The other tests run with a fixed code, which switches it on.
 */
@IntegrationTest
@TestPropertySource(properties = {"hiwiski.setup-code=", "hiwiski.setup-code-required=false"})
class SetupWithoutCodeIT {

    @Autowired RestTestClient rest;

    @Test
    void theHandshakeSaysNoCodeIsAskedFor() {
        rest.get()
                .uri("/api/v1/handshake")
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.setupCodeRequired")
                .isEqualTo(false);
    }

    @Test
    void theWizardRunsWithoutACode() {
        rest.post()
                .uri("/api/v1/setup")
                .contentType(MediaType.APPLICATION_JSON)
                .body(setup())
                .exchange()
                .expectStatus()
                .isCreated();
    }

    /** Where no code is asked for, the check before the steps lets every code through. */
    @Test
    void theCheckBeforeTheStepsTakesAnyCode() {
        rest.post()
                .uri("/api/v1/setup/code")
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("setupCode", "IRGEND-WAS"))
                .exchange()
                .expectStatus()
                .isNoContent();
    }

    /** An app from before the code became optional still sends what was typed. */
    @Test
    void aCodeSentAnywayIsIgnored() {
        var body = new java.util.HashMap<String, Object>(setup());
        body.put("setupCode", "IRGEND-WAS");
        rest.post()
                .uri("/api/v1/setup")
                .contentType(MediaType.APPLICATION_JSON)
                .body(body)
                .exchange()
                .expectStatus()
                .isCreated();
    }

    /**
     * Restoring on a fresh server needs no code either: an upload without the header
     * gets past it, to the check that the file is an archive at all.
     */
    @Test
    void anUploadGetsPastTheCodeWithoutTheHeader() {
        rest.post()
                .uri("/api/v1/setup/uploads")
                .contentType(MediaType.APPLICATION_OCTET_STREAM)
                .body(new byte[] {1, 2, 3})
                .exchange()
                .expectStatus()
                .isBadRequest()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("admin.backup_invalid");
    }

    /** Without the code the wizard is still open only once. */
    @Test
    void theWizardStaysClosedOnceItHasRun() {
        rest.post()
                .uri("/api/v1/setup")
                .contentType(MediaType.APPLICATION_JSON)
                .body(setup())
                .exchange()
                .expectStatus()
                .isCreated();
        rest.post()
                .uri("/api/v1/setup")
                .contentType(MediaType.APPLICATION_JSON)
                .body(setup())
                .exchange()
                .expectStatus()
                .isEqualTo(409)
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("setup.already_completed");
    }

    private static Map<String, Object> setup() {
        return Map.of(
                "backupPassword", Family.BACKUP_PASSWORD,
                "familyName", "Familie Probe",
                "timezone", "Europe/Berlin",
                "admin", Map.of("displayName", "Anna", "username", "anna", "password", "geheim-genug"),
                "groups", List.of("Everyone"),
                "device", Map.of("deviceName", "Handy", "platform", "IOS"));
    }
}
