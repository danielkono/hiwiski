package de.danielkononov.hiwiski.sync;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Map;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.test.web.servlet.client.RestTestClient;

@IntegrationTest
class EventStreamIT {

    @Autowired RestTestClient rest;

    @Value("${local.server.port}")
    int port;

    /** An open stream, read line by line as it comes. */
    private record Stream(HttpClient http, BlockingQueue<String> lines) {

        /** The next line that starts with [prefix], or a failure after [timeout]. */
        String await(String prefix, Duration timeout) throws InterruptedException {
            long until = System.nanoTime() + timeout.toNanos();
            while (true) {
                String line = lines.poll(until - System.nanoTime(), TimeUnit.NANOSECONDS);
                if (line == null) {
                    throw new AssertionError("no " + prefix + " within " + timeout);
                }
                if (line.startsWith(prefix)) {
                    return line;
                }
            }
        }
    }

    private Stream open(Family.Session device) {
        var ticket = rest.post()
                .uri("/api/v1/events/ticket")
                .headers(device.auth())
                .exchange()
                .expectStatus()
                .isCreated()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody()
                .get("ticket");
        var http = HttpClient.newHttpClient();
        var lines = new LinkedBlockingQueue<String>();
        http.sendAsync(
                        HttpRequest.newBuilder(
                                        URI.create("http://localhost:" + port + "/api/v1/events?ticket=" + ticket))
                                .header("Accept", "text/event-stream")
                                .build(),
                        HttpResponse.BodyHandlers.ofLines())
                .thenAccept(response -> response.body().forEach(lines::add));
        return new Stream(http, lines);
    }

    /**
     * Waits for the stream's first event -- the server sends the current position
     * first -- instead of a fixed pause: on a slow runner the device was revoked before
     * the stream was registered, and the revocation never came.
     */
    @Test
    void aSignedOutDeviceHearsItOnItsStream() throws Exception {
        var phone = Family.setUp(rest);
        var laptop = Family.login(rest, "anna", "geheim-genug", "Laptop");
        var stream = open(laptop);
        try {
            stream.await("event:seq", Duration.ofSeconds(10));

            rest.delete()
                    .uri("/api/v1/devices/" + laptop.deviceId())
                    .headers(phone.auth())
                    .exchange()
                    .expectStatus()
                    .isNoContent();

            stream.await("event:revoked", Duration.ofSeconds(10));
        } finally {
            stream.http().shutdownNow();
        }
    }

    @org.springframework.beans.factory.annotation.Autowired
    de.danielkononov.hiwiski.platform.RestoreInProgress restore;

    /**
     * A restore begins: every app hears it at once and stops taking changes -- not at
     * its next start. One that connects while it runs hears it right away.
     */
    @Test
    void everyStreamHearsARestore() throws Exception {
        var phone = Family.setUp(rest);
        var stream = open(phone);
        Stream late = null;
        try {
            stream.await("event:seq", Duration.ofSeconds(10));
            restore.begin();
            stream.await("event:restoring", Duration.ofSeconds(10));
            org.assertj.core.api.Assertions.assertThat(stream.await("data:", Duration.ofSeconds(10)))
                    .isEqualTo("data:true");

            late = open(phone);
            late.await("event:restoring", Duration.ofSeconds(10));

            restore.end();
            stream.await("event:restoring", Duration.ofSeconds(10));
            org.assertj.core.api.Assertions.assertThat(stream.await("data:", Duration.ofSeconds(10)))
                    .isEqualTo("data:false");
        } finally {
            restore.end();
            stream.http().shutdownNow();
            if (late != null) {
                late.http().shutdownNow();
            }
        }
    }

    /**
     * The phone's stream still carries what happens after the laptop is signed out --
     * not merely "still open after a second", which a stream closed later would pass.
     */
    @Test
    void anotherDeviceOfTheSameMemberKeepsItsStream() throws Exception {
        var phone = Family.setUp(rest);
        var laptop = Family.login(rest, "anna", "geheim-genug", "Laptop");
        var stream = open(phone);
        try {
            stream.await("event:seq", Duration.ofSeconds(10));
            rest.delete()
                    .uri("/api/v1/devices/" + laptop.deviceId())
                    .headers(phone.auth())
                    .exchange()
                    .expectStatus()
                    .isNoContent();

            new de.danielkononov.hiwiski.support.SyncClient(rest, phone)
                    .push(de.danielkononov.hiwiski.support.SyncClient.mutation(
                            "TODO_LIST", java.util.UUID.randomUUID(), null, Map.of("name", "After")));

            stream.await("event:seq", Duration.ofSeconds(10));
        } finally {
            // Hang up, or the server waits for this stream when it shuts down.
            stream.http().shutdownNow();
        }
    }

    /** A ticket fetched before the device was signed out opens nothing afterwards. */
    @Test
    void aTicketDoesNotOutliveItsDevice() throws Exception {
        var phone = Family.setUp(rest);
        var laptop = Family.login(rest, "anna", "geheim-genug", "Laptop");
        var ticket = rest.post()
                .uri("/api/v1/events/ticket")
                .headers(laptop.auth())
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody()
                .get("ticket");

        rest.delete()
                .uri("/api/v1/devices/" + laptop.deviceId())
                .headers(phone.auth())
                .exchange()
                .expectStatus()
                .isNoContent();

        // As soon as the headers are there: an opened stream would not end on its own.
        var http = HttpClient.newHttpClient();
        try {
            var response = http.send(
                    HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api/v1/events?ticket=" + ticket))
                            .header("Accept", "text/event-stream")
                            .timeout(Duration.ofSeconds(10))
                            .build(),
                    HttpResponse.BodyHandlers.ofInputStream());
            response.body().close();
            assertThat(response.statusCode()).isEqualTo(403);
        } finally {
            http.shutdownNow();
        }
    }
}
