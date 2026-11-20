package de.danielkononov.hiwiski.identity;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.client.RestTestClient;

@IntegrationTest
class SetupIT {

    @Autowired RestTestClient rest;

    @Test
    void aFreshInstanceReportsItselfAsNotSetUp() {
        rest.get()
                .uri("/api/v1/handshake")
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.setupCompleted")
                .isEqualTo(false);
    }

    @Test
    void theWizardCreatesFamilyAdminAndGroupsAndSignsInRightAway() {
        var session = Family.setUp(rest);

        // Signed in right away: otherwise the first member would have to sign in again
        // immediately after creating everything.
        rest.get()
                .uri("/api/v1/auth/session")
                .headers(session.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.member.isAdmin")
                .isEqualTo(true)
                .jsonPath("$.mustChangePassword")
                .isEqualTo(false);

        rest.get()
                .uri("/api/v1/handshake")
                .exchange()
                .expectBody()
                .jsonPath("$.setupCompleted")
                .isEqualTo(true)
                .jsonPath("$.familyName")
                .isEqualTo("Familie Probe");

        // Setup creates two groups.
        rest.get()
                .uri("/api/v1/groups")
                .headers(session.auth())
                .exchange()
                .expectBody()
                .jsonPath("$.groups.length()")
                .isEqualTo(2)
                .jsonPath("$.groups[0].name")
                .isEqualTo("Everyone");
    }

    @Test
    void theWizardRunsExactlyOnce() {
        Family.setUp(rest);

        rest.post()
                .uri("/api/v1/setup")
                .contentType(MediaType.APPLICATION_JSON)
                .body(
                        Map.of(
                                "setupCode", Family.SETUP_CODE,
                                "backupPassword", Family.BACKUP_PASSWORD,
                                "familyName", "Zweite Familie",
                                "timezone", "Europe/Berlin",
                                "admin",
                                        Map.of(
                                                "displayName", "Eindringling",
                                                "username", "boese",
                                                "password", "auch-lang-genug"),
                                "groups", List.of("Everyone"),
                                "device", Map.of("deviceName", "Laptop", "platform", "WEB")))
                .exchange()
                .expectStatus()
                .isEqualTo(409)
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("setup.already_completed");
    }

    /**
     * The wizard checks the code before its steps: a wrong one is said at once, not
     * after everything is filled in.
     */
    @Test
    void theCodeIsCheckedBeforeTheSteps() {
        assertThat(checkCode("WRON-GCOD")).as("a wrong code").isEqualTo(403);
        assertThat(checkCode("test-code")).as("the code, typed in lower case").isEqualTo(204);
        rest.get()
                .uri("/api/v1/handshake")
                .exchange()
                .expectBody()
                .jsonPath("$.setupCompleted")
                .isEqualTo(false);
    }

    /** Set up already: said only to whoever holds the code. */
    @Test
    void aCheckAfterTheSetupIsAConflictOnlyWithTheCode() {
        Family.setUp(rest);
        assertThat(checkCode(Family.SETUP_CODE)).as("with the code").isEqualTo(409);
        assertThat(checkCode("WRON-GCOD")).as("without it").isEqualTo(403);
    }

    private int checkCode(String code) {
        return rest.post()
                .uri("/api/v1/setup/code")
                // An address of its own: the wrong codes here spend no other test's budget.
                .header("X-Forwarded-For", "203.0.113.21")
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("setupCode", code))
                .exchange()
                .returnResult(Map.class)
                .getStatus()
                .value();
    }

    @Test
    void anInvalidTimezoneAbortsAndLeavesNothingHalfDone() {
        rest.post()
                .uri("/api/v1/setup")
                .contentType(MediaType.APPLICATION_JSON)
                .body(
                        Map.of(
                                "setupCode", Family.SETUP_CODE,
                                "backupPassword", Family.BACKUP_PASSWORD,
                                "familyName", "Familie Probe",
                                "timezone", "Mittelerde/Auenland",
                                "admin",
                                        Map.of(
                                                "displayName", "Anna",
                                                "username", "anna",
                                                "password", "geheim-genug"),
                                "device", Map.of("deviceName", "Handy", "platform", "IOS")))
                .exchange()
                .expectStatus()
                .isBadRequest()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("setup.timezone_invalid");

        // Everything in one transaction: no half a family, no administrator without
        // groups -- and the wizard can be run again.
        rest.get()
                .uri("/api/v1/handshake")
                .exchange()
                .expectBody()
                .jsonPath("$.setupCompleted")
                .isEqualTo(false);
    }

    /**
     * A device used without a server brings its member's id: every item it
     * created names that id, and the administrator is created under it.
     */
    @Test
    void theAdministratorKeepsTheIdTheAppBrings() {
        var id = UUID.randomUUID();
        var body =
                rest.post()
                        .uri("/api/v1/setup")
                        .contentType(MediaType.APPLICATION_JSON)
                        .body(
                                Map.of(
                                        "setupCode", Family.SETUP_CODE,
                                        "backupPassword", Family.BACKUP_PASSWORD,
                                        "familyName", "Familie Lokal",
                                        "timezone", "Europe/Berlin",
                                        "admin",
                                                Map.of(
                                                        "id", id.toString(),
                                                        "displayName", "Anna",
                                                        "username", "anna",
                                                        "password", "geheim-genug"),
                                        "device", Map.of("deviceName", "Annas iPhone", "platform", "IOS")))
                        .exchange()
                        .expectStatus()
                        .isCreated()
                        .expectBody(Map.class)
                        .returnResult()
                        .getResponseBody();

        assertThat(Family.toSession(body).memberId()).isEqualTo(id);
    }
}
