package de.danielkononov.hiwiski.security;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.IntegrationTest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * The server itself tells the browser what its web client may load and where it may
 * connect -- behind any proxy or none (identity.internal.SecurityHeaders).
 *
 *
 */
@IntegrationTest
class SecurityHeadersIT {

    @Autowired RestTestClient rest;

    @Test
    void theWebClientGetsAContentSecurityPolicy() {
        for (var path : new String[] {"/", "/index.html", "/wiki/some/page", "/api/v1/handshake"}) {
            var headers = rest.get().uri(path).exchange().returnResult().getResponseHeaders();
            var csp = headers.getFirst("Content-Security-Policy");
            assertThat(csp).as(path).isNotNull();
            assertThat(csp)
                    .as(path)
                    .contains("default-src 'self'")
                    // CanvasKit and sqlite3.wasm; no plain eval, no inline scripts, and
                    // nothing from another host.
                    .contains("script-src 'self' 'wasm-unsafe-eval';")
                    .doesNotContain("'unsafe-eval'")
                    .doesNotContain("https:")
                    .contains("connect-src 'self';")
                    .contains("frame-ancestors 'none'")
                    .contains("base-uri 'self'")
                    .contains("object-src 'none'");
            assertThat(headers.getFirst("Referrer-Policy")).as(path).isEqualTo("no-referrer");
            assertThat(headers.getFirst("Permissions-Policy"))
                    .as(path)
                    .contains("camera=()")
                    .contains("microphone=()");
            // Spring's defaults stay.
            assertThat(headers.getFirst("X-Frame-Options")).as(path).isEqualTo("DENY");
            assertThat(headers.getFirst("X-Content-Type-Options")).as(path).isEqualTo("nosniff");
        }
    }
}
