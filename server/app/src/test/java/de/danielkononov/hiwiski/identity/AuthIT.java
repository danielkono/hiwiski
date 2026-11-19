package de.danielkononov.hiwiski.identity;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.client.RestTestClient;

@IntegrationTest
class AuthIT {

    @Autowired RestTestClient rest;

    @Test
    void withoutATokenItIs401Not403() {
        // The contract distinguishes: 401 means "not signed in", 403 "not shared". A client
        // that cannot tell the two apart does not know whether to show the sign-in screen
        // or write a message.
        rest.get()
                .uri("/api/v1/auth/session")
                .exchange()
                .expectStatus()
                .isUnauthorized()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("auth.required");
    }

    @Test
    void wrongPasswordAndUnknownUserLookTheSame() {
        Family.setUp(rest);

        // The difference would reveal which usernames exist.
        for (var credentials :
                java.util.List.of(
                        Map.of("username", "anna", "password", "falsch-aber-lang"),
                        Map.of("username", "doesnotexist", "password", "falsch-aber-lang"))) {
            rest.post()
                    .uri("/api/v1/auth/login")
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(
                            Map.of(
                                    "username", credentials.get("username"),
                                    "password", credentials.get("password"),
                                    "device", Map.of("deviceName", "Laptop", "platform", "WEB")))
                    .exchange()
                    .expectStatus()
                    .isUnauthorized()
                    .expectBody()
                    .jsonPath("$.code")
                    .isEqualTo("auth.invalid_credentials");
        }
    }

    @Test
    void signingOutLocksOutExactlyThisDevice() {
        var phone = Family.setUp(rest);
        var laptop = Family.login(rest, "anna", "geheim-genug", "Laptop");

        rest.post().uri("/api/v1/auth/logout").headers(laptop.auth()).exchange().expectStatus().isNoContent();

        // Takes effect immediately -- that is exactly why there is no JWT.
        rest.get().uri("/api/v1/auth/session").headers(laptop.auth()).exchange().expectStatus().isUnauthorized();
        rest.get().uri("/api/v1/auth/session").headers(phone.auth()).exchange().expectStatus().isOk();
    }

    @Test
    void aResetPasswordLocksTheSessionUntilANewOneIsSet() {
        var admin = Family.setUp(rest);

        var ben =
                rest.post()
                        .uri("/api/v1/members")
                        .headers(admin.auth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .body(
                                Map.of(
                                        "displayName", "Ben",
                                        "username", "ben",
                                        "password", "bens-erstes-passwort"))
                        .exchange()
                        .expectStatus()
                        .isCreated()
                        .expectBody(Map.class)
                        .returnResult()
                        .getResponseBody();

        String temporary =
                (String)
                        rest.post()
                                .uri("/api/v1/members/" + ben.get("id") + "/password-reset")
                                .headers(admin.auth())
                                .exchange()
                                .expectStatus()
                                .isOk()
                                .expectBody(Map.class)
                                .returnResult()
                                .getResponseBody()
                                .get("temporaryPassword");

        var bensSession = Family.login(rest, "ben", temporary, "Bens Handy");

        // The session may change the password -- and nothing else. A state in which the
        // user can use the app and swipe the prompt away would not be a prompt.
        rest.get()
                .uri("/api/v1/members")
                .headers(bensSession.auth())
                .exchange()
                .expectStatus()
                .isForbidden()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("auth.password_change_required");

        // Querying the session stays allowed: otherwise after a restart the app would not
        // know why it is stuck.
        rest.get()
                .uri("/api/v1/auth/session")
                .headers(bensSession.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.mustChangePassword")
                .isEqualTo(true);

        // Handshake and sign-in stay reachable even when the app sends the old token
        // along -- otherwise it considers the server unreachable at startup and never
        // gets as far as the password change.
        rest.get()
                .uri("/api/v1/handshake")
                .headers(bensSession.auth())
                .exchange()
                .expectStatus()
                .isOk();
        rest.post()
                .uri("/api/v1/auth/login")
                .headers(bensSession.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(
                        Map.of(
                                "username", "ben",
                                "password", temporary,
                                "device", Map.of("deviceName", "Bens Handy", "platform", "ANDROID")))
                .exchange()
                .expectStatus()
                .isOk();

        rest.post()
                .uri("/api/v1/auth/password")
                .headers(bensSession.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("currentPassword", temporary, "newPassword", "bens-eigenes-passwort"))
                .exchange()
                .expectStatus()
                .isNoContent();

        rest.get().uri("/api/v1/members").headers(bensSession.auth()).exchange().expectStatus().isOk();
    }

    @Test
    void onlyTheContainerCommandResetsTheAdministratorsPassword() {
        var admin = Family.setUp(rest);

        // There is nobody above him, and there is no email. A way through the app
        // would be a way to take him over.
        rest.post()
                .uri("/api/v1/members/" + admin.memberId() + "/password-reset")
                .headers(admin.auth())
                .exchange()
                .expectStatus()
                .isBadRequest()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("identity.admin_password_needs_container_command");
    }

    /**
     * After a few wrong passwords, the next attempt has to wait -- and is told how long,
     * instead of a request that sleeps while it holds a database connection.
     */
    @Test
    void tooManyAttemptsAreAnsweredWithRetryAfter() {
        Family.setUp(rest);
        // A name of its own: the counts live in memory for the whole test run.
        String username = "guess-" + java.util.UUID.randomUUID();
        java.util.function.Supplier<org.springframework.test.web.servlet.client.RestTestClient.ResponseSpec> attempt =
                () -> rest.post()
                        .uri("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .body(Map.of(
                                "username", username,
                                "password", "falsch-aber-lang",
                                "device", Map.of("deviceName", "Laptop", "platform", "WEB")))
                        .exchange();

        for (int i = 0; i < 5; i++) {
            attempt.get().expectStatus().isUnauthorized();
        }
        attempt.get()
                .expectStatus()
                .isEqualTo(429)
                .expectHeader()
                .exists("Retry-After")
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("auth.too_many_attempts");
    }

    /** A name has to be one when it is changed, too. */
    @Test
    void aBlankDisplayNameIsRefused() {
        var anna = Family.setUp(rest);
        rest.patch()
                .uri("/api/v1/members/" + anna.memberId())
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("displayName", "   "))
                .exchange()
                .expectStatus()
                .isBadRequest()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("identity.display_name_required");
    }

    /**
     * A change to the password one has already is none. After a reset it left the
     * temporary password in place -- the one the administrator knows -- and took the
     * prompt away.
     */
    @Test
    void theNewPasswordIsNotTheCurrentOne() {
        var anna = Family.setUp(rest, "anna", "geheim-genug");

        rest.post()
                .uri("/api/v1/auth/password")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("currentPassword", "geheim-genug", "newPassword", "geheim-genug"))
                .exchange()
                .expectStatus()
                .isBadRequest()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("auth.new_password_same");
    }
}
