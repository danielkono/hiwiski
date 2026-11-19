package de.danielkononov.hiwiski.platform;

import static org.assertj.core.api.Assertions.assertThat;

import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/** A foreign body is read up to its limit and no further. */
class LimitedBodyTest {

    private HttpServer server;
    private final HttpClient http = HttpClient.newHttpClient();

    @BeforeEach
    void start() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        // Endless, without a length: the kind of body that filled the heap.
        server.createContext("/endless", exchange -> {
            exchange.sendResponseHeaders(200, 0);
            var chunk = new byte[64 * 1024];
            try (var out = exchange.getResponseBody()) {
                for (int i = 0; i < 1024; i++) {
                    out.write(chunk);
                }
            } catch (IOException closedByClient) {
                // The reader stopped, as it should.
            }
        });
        server.createContext("/declared", exchange -> {
            // Claims a gigabyte; the reader must not wait for it.
            exchange.sendResponseHeaders(200, 999_999_999);
            try (var out = exchange.getResponseBody()) {
                out.write(new byte[16]);
                out.flush();
            } catch (IOException closedByClient) {
                // Expected.
            }
        });
        server.createContext("/latin", exchange -> {
            var body = "Kürbis".getBytes(StandardCharsets.ISO_8859_1);
            exchange.getResponseHeaders().add("Content-Type", "text/plain; charset=ISO-8859-1");
            exchange.sendResponseHeaders(200, body.length);
            try (var out = exchange.getResponseBody()) {
                out.write(body);
            }
        });
        server.start();
    }

    @AfterEach
    void stop() {
        server.stop(0);
    }

    private HttpResponse<java.io.InputStream> get(String path) throws Exception {
        return http.send(
                HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + server.getAddress().getPort() + path))
                        .build(),
                HttpResponse.BodyHandlers.ofInputStream());
    }

    @Test
    void aBodyPastTheLimitIsNotReadToItsEnd() throws Exception {
        assertThat(LimitedBody.read(get("/endless"), 100_000)).isEmpty();
    }

    @Test
    void aDeclaredLengthPastTheLimitIsRefusedUpFront() throws Exception {
        assertThat(LimitedBody.read(get("/declared"), 100_000)).isEmpty();
    }

    @Test
    void theCharsetIsTheOneTheServerNames() throws Exception {
        assertThat(LimitedBody.read(get("/latin"), 100)).contains("Kürbis");
    }
}
