package de.danielkononov.hiwiski.identity;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import static de.danielkononov.hiwiski.db.generated.Tables.DEVICE;

import java.time.OffsetDateTime;
import java.util.Map;
import java.util.UUID;
import org.jooq.DSLContext;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.client.RestTestClient;

@IntegrationTest
class DeviceIT {

    @Autowired RestTestClient rest;
    @Autowired DSLContext db;

    private static Map<String, Object> device(String name, UUID installation, boolean stay) {
        return Map.of(
                "deviceName", name,
                "platform", "WEB",
                "installationId", installation.toString(),
                "staySignedIn", stay);
    }

    private int listed(Family.Session session) {
        return rest.get()
                .uri("/api/v1/devices")
                .headers(session.auth())
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody()
                .get("devices") instanceof java.util.List<?> list
                ? list.size()
                : -1;
    }

    /**
     * Signing in again on the same browser added a row each time: the device list filled
     * with entries whose token nobody held any more.
     */
    @Test
    void signingInAgainFromAnInstallationReplacesItsDevice() {
        var phone = Family.setUp(rest);
        var browser = UUID.randomUUID();
        var first = Family.login(rest, "anna", "geheim-genug", device("Firefox", browser, true));
        var second = Family.login(rest, "anna", "geheim-genug", device("Firefox", browser, true));

        rest.get().uri("/api/v1/devices").headers(first.auth()).exchange().expectStatus().isUnauthorized();
        rest.get().uri("/api/v1/devices").headers(second.auth()).exchange().expectStatus().isOk();
        // The phone and the browser -- not the browser twice.
        org.assertj.core.api.Assertions.assertThat(listed(phone)).isEqualTo(2);
    }

    @Test
    void aSessionWithoutStaySignedInEndsAfterTwelveIdleHours() {
        var phone = Family.setUp(rest);
        var shared = Family.login(rest, "anna", "geheim-genug", device("Library PC", UUID.randomUUID(), false));
        rest.get().uri("/api/v1/devices").headers(shared.auth()).exchange().expectStatus().isOk();

        db.update(DEVICE)
                .set(DEVICE.LAST_SEEN_AT, OffsetDateTime.now().minusHours(13))
                .where(DEVICE.ID.eq(shared.deviceId()))
                .execute();

        rest.get().uri("/api/v1/devices").headers(shared.auth()).exchange().expectStatus().isUnauthorized();
        org.assertj.core.api.Assertions.assertThat(listed(phone)).isEqualTo(1);
    }

    @Test
    void aDeviceThatStaysSignedInSurvivesIdleHoursButNotHalfAYear() {
        var phone = Family.setUp(rest);
        var tablet = Family.login(rest, "anna", "geheim-genug", device("Tablet", UUID.randomUUID(), true));

        db.update(DEVICE)
                .set(DEVICE.LAST_SEEN_AT, OffsetDateTime.now().minusDays(30))
                .where(DEVICE.ID.eq(tablet.deviceId()))
                .execute();
        rest.get().uri("/api/v1/devices").headers(tablet.auth()).exchange().expectStatus().isOk();

        db.update(DEVICE)
                .set(DEVICE.LAST_SEEN_AT, OffsetDateTime.now().minusDays(181))
                .where(DEVICE.ID.eq(tablet.deviceId()))
                .execute();
        rest.get().uri("/api/v1/devices").headers(tablet.auth()).exchange().expectStatus().isUnauthorized();
        org.assertj.core.api.Assertions.assertThat(listed(phone)).isEqualTo(1);
    }

    @Test
    void theListMarksTheOwnDevice() {
        var phone = Family.setUp(rest);
        Family.login(rest, "anna", "geheim-genug", "Laptop");

        rest.get()
                .uri("/api/v1/devices")
                .headers(phone.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.devices.length()")
                .isEqualTo(2)
                // The own device has no "Sign out" -- the UI needs the marker to leave out
                // the button.
                .jsonPath("$.devices[?(@.name=='Annas iPhone')].current")
                .isEqualTo(true)
                .jsonPath("$.devices[?(@.name=='Laptop')].current")
                .isEqualTo(false);
    }

    @Test
    void lockingOutTakesEffectImmediately() {
        var phone = Family.setUp(rest);
        var laptop = Family.login(rest, "anna", "geheim-genug", "Laptop");

        rest.delete()
                .uri("/api/v1/devices/" + laptop.deviceId())
                .headers(phone.auth())
                .exchange()
                .expectStatus()
                .isNoContent();

        rest.get().uri("/api/v1/devices").headers(laptop.auth()).exchange().expectStatus().isUnauthorized();
        rest.get().uri("/api/v1/devices").headers(phone.auth()).exchange().expectStatus().isOk();
    }

    @Test
    void otherMembersDevicesDoNotExistForMe() {
        var admin = Family.setUp(rest);
        var invitation =
                rest.post()
                        .uri("/api/v1/invitations")
                        .headers(admin.auth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .body(Map.of("validity", "HOURS_24"))
                        .exchange()
                        .expectBody(Map.class)
                        .returnResult()
                        .getResponseBody();

        var bensSignIn =
                rest.post()
                        .uri("/api/v1/invitations/" + invitation.get("code") + "/redeem")
                        .contentType(MediaType.APPLICATION_JSON)
                        .body(
                                Map.of(
                                        "displayName", "Ben",
                                        "username", "ben",
                                        "password", "bens-langes-passwort",
                                        "device", Map.of("deviceName", "Bens Tablet", "platform", "ANDROID")))
                        .exchange()
                        .expectBody(Map.class)
                        .returnResult()
                        .getResponseBody();
        var ben = Family.toSession(bensSignIn);

        // Not even the administrator sees other members' devices: he may run the server,
        // not see other members' content. 404 instead of 403 -- the
        // existence of someone else's device is nobody's business.
        rest.delete()
                .uri("/api/v1/devices/" + ben.deviceId())
                .headers(admin.auth())
                .exchange()
                .expectStatus()
                .isNotFound();
        // And it did nothing: an implementation that revoked the device and then
        // answered 404 would lock Ben out behind a green test.
        rest.get()
                .uri("/api/v1/auth/session")
                .headers(ben.auth())
                .exchange()
                .expectStatus()
                .isOk();

        rest.get()
                .uri("/api/v1/devices")
                .headers(admin.auth())
                .exchange()
                .expectBody()
                .jsonPath("$.devices.length()")
                .isEqualTo(1);
    }
}
