package de.danielkononov.hiwiski.platform;

import de.danielkononov.hiwiski.support.IntegrationTest;
import java.util.List;
import java.util.stream.Collectors;
import java.util.stream.IntStream;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * **A browser that names many languages is served like any other.** Tomcat refused
 * more than ten, and the page and every call of the API answered 500.
 */
@IntegrationTest
class AcceptLanguageIT {

    @Autowired RestTestClient rest;

    /** As a phone set up with many languages sends it. */
    private static final String MANY = IntStream.range(0, 24)
            .mapToObj(i -> List.of("de-DE", "de", "en-US", "en", "fr", "it", "es", "nl", "pl", "tr", "ru", "pt")
                            .get(i % 12)
                    + ";q=0." + (9 - i % 9))
            .collect(Collectors.joining(","));

    @Test
    void theApiAnswersARequestNamingManyLanguages() {
        rest.get()
                .uri("/api/v1/handshake")
                .header("Accept-Language", MANY)
                .exchange()
                .expectStatus()
                .isOk();
    }
}
