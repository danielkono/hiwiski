package de.danielkononov.hiwiski.platform;

import de.danielkononov.hiwiski.support.IntegrationTest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.web.servlet.client.RestTestClient;

@IntegrationTest
class HandshakeIT {

    @Autowired RestTestClient rest;

    @Test
    void handshakeIsReachableWithoutSignIn() {
        rest.get()
                .uri("/api/v1/handshake")
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.apiVersion")
                .isEqualTo("v1")
                // A fresh instance is not set up -- and therefore names no family name
                // either. An empty placeholder would be a claim.
                .jsonPath("$.setupCompleted")
                .isEqualTo(false)
                .jsonPath("$.familyName")
                .doesNotExist()
                // The tests run with a fixed setup code, which switches it on.
                .jsonPath("$.setupCodeRequired")
                .isEqualTo(true)
                // A family's own server names no legal notice: it needs none.
                .jsonPath("$.legalNoticeUrl")
                .doesNotExist()
                .jsonPath("$.privacyUrl")
                .doesNotExist();
    }

    @Test
    void everythingElseNeedsASignIn() {
        // An unknown API path must not return a page with status 200 -- otherwise the
        // client would not recognize the error as one.
        rest.get().uri("/api/v1/does-not-exist").exchange().expectStatus().isUnauthorized();
    }

    /** A request's own mistake is a 4xx -- not a server error with a stack trace. */
    @Test
    void theRequestsMistakesAreNotServerErrors() {
        var anna = de.danielkononov.hiwiski.support.Family.setUp(rest);
        rest.get().uri("/api/v1/doesnotexist").headers(anna.auth()).exchange().expectStatus().isNotFound();
        rest.post()
                .uri("/api/v1/trash/TODO/not-a-uuid/restore")
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isBadRequest();
        rest.delete().uri("/api/v1/handshake").headers(anna.auth()).exchange().expectStatus().isEqualTo(405);
    }
}
