package de.danielkononov.hiwiski.platform;

import de.danielkononov.hiwiski.support.IntegrationTest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.client.RestTestClient;

/** An instance open to the public names its operator's legal pages. */
@IntegrationTest
@TestPropertySource(
        properties = {
            "hiwiski.legal-notice-url=https://hiwiski.example.org/impressum",
            "hiwiski.privacy-url=https://hiwiski.example.org/datenschutz"
        })
class PublicInstanceHandshakeIT {

    @Autowired RestTestClient rest;

    @Test
    void theHandshakeNamesTheLegalPages() {
        rest.get()
                .uri("/api/v1/handshake")
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.legalNoticeUrl")
                .isEqualTo("https://hiwiski.example.org/impressum")
                .jsonPath("$.privacyUrl")
                .isEqualTo("https://hiwiski.example.org/datenschutz");
    }
}
