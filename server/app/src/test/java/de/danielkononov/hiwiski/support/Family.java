package de.danielkononov.hiwiski.support;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpHeaders;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * Sets up a family and signs in devices.
 *
 * <p>So that a test does not start with twenty lines of preparation in which the actual
 * case gets lost.
 */
public final class Family {

    private Family() {}

    /** A signed-in device. */
    public record Session(String token, UUID memberId, UUID deviceId) {

        public java.util.function.Consumer<HttpHeaders> auth() {
            return headers -> headers.setBearerAuth(token);
        }
    }

    /** The setup code the test profile sets (application-test.yaml). */
    public static final String SETUP_CODE = "TEST-CODE";

    /** The backup password the wizard sets -- every archive in the tests opens with it. */
    public static final String BACKUP_PASSWORD = "backup-passwort";

    /** A run through the setup wizard. Exactly once per instance. */
    public static Session setUp(RestTestClient rest) {
        return setUp(rest, "anna", "geheim-genug");
    }

    public static Session setUp(RestTestClient rest, String username, String password) {
        var body =
                rest.post()
                        .uri("/api/v1/setup")
                        .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                        .body(
                                Map.of(
                                        "setupCode", SETUP_CODE,
                                        "backupPassword", BACKUP_PASSWORD,
                                        "familyName", "Familie Probe",
                                        "timezone", "Europe/Berlin",
                                        "admin",
                                                Map.of(
                                                        "displayName", "Anna",
                                                        "username", username,
                                                        "password", password),
                                        "groups", List.of("Everyone", "Parents"),
                                        "device",
                                                Map.of(
                                                        "deviceName", "Annas iPhone",
                                                        "platform", "IOS")))
                        .exchange()
                        .expectStatus()
                        .isCreated()
                        .expectBody(Map.class)
                        .returnResult()
                        .getResponseBody();
        return toSession(body);
    }

    public static Session login(RestTestClient rest, String username, String password, String deviceName) {
        return login(rest, username, password, Map.of("deviceName", deviceName, "platform", "ANDROID"));
    }

    /** A sign-in with the device registration as given. */
    public static Session login(RestTestClient rest, String username, String password, Map<String, ?> device) {
        var body =
                rest.post()
                        .uri("/api/v1/auth/login")
                        .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                        .body(
                                Map.of(
                                        "username", username,
                                        "password", password,
                                        "device", device))
                        .exchange()
                        .expectStatus()
                        .isOk()
                        .expectBody(Map.class)
                        .returnResult()
                        .getResponseBody();
        return toSession(body);
    }

    @SuppressWarnings("unchecked")
    public static Session toSession(Map<?, ?> signedIn) {
        Map<String, Object> session = (Map<String, Object>) signedIn.get("session");
        Map<String, Object> member = (Map<String, Object>) session.get("member");
        return new Session(
                (String) signedIn.get("token"),
                UUID.fromString((String) member.get("id")),
                UUID.fromString((String) session.get("deviceId")));
    }
}
