package de.danielkononov.hiwiski.support;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Lazy;
import org.springframework.core.env.Environment;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * An HTTP client pointed at the server started for the test.
 *
 * <p>The tests deliberately go through real HTTP rather than MockMvc: serialization,
 * status codes and the security chain belong under test too, and those are exactly what
 * MockMvc partly skips.
 */
@TestConfiguration(proxyBeanMethods = false)
public class TestHttpClient {

    /**
     * Lazy because {@code local.server.port} is only known once the web server is running --
     * and that happens after the regular singletons are created.
     */
    @Bean
    @Lazy
    RestTestClient restTestClient(Environment environment) {
        return RestTestClient.bindToServer()
                .baseUrl("http://localhost:" + environment.getProperty("local.server.port"))
                .build();
    }
}
