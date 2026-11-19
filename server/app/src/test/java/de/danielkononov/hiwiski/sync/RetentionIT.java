package de.danielkononov.hiwiski.sync;

import static de.danielkononov.hiwiski.db.generated.Tables.CHANGE_LOG;
import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.util.Map;
import java.util.UUID;
import org.jooq.DSLContext;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * The second part of the sync acceptance case: "A device offline for 100 days (log
 * retention exceeded) → clean resync with a visible list of what was rejected."
 */
@IntegrationTest
class RetentionIT {

    private static final String LIST = "TODO_LIST";

    @Autowired RestTestClient rest;

    @Autowired DSLContext db;

    @Test
    void aDeviceBehindTheLogRetentionGetsResyncRequired() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);

        for (String name : new String[] {"Haushalt", "Garten", "Keller"}) {
            device.push(SyncClient.mutation(LIST, UUID.randomUUID(), null, Map.of("name", name)));
        }
        device.pullAll();
        long devicePosition = device.lastSeq();
        assertThat(devicePosition).isGreaterThan(1);

        // Something else happens, then cleanup runs: the position of a second device that
        // has been away longer now lies before the oldest log entry.
        device.push(SyncClient.mutation(LIST, UUID.randomUUID(), null, Map.of("name", "Dachboden")));
        db.deleteFrom(CHANGE_LOG).where(CHANGE_LOG.SEQ.lt(devicePosition)).execute();

        device.setLastSeq(1);
        var response = device.pullOnce();

        assertThat(response.get("resyncRequired")).isEqualTo(true);
        // No partial data: the client should first flush its outbox, then discard locally
        // and reload.
        assertThat((java.util.List<?>) response.get("changes")).isEmpty();
    }

    @Test
    void aFreshDeviceNeedsNoResync() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);
        device.push(SyncClient.mutation(LIST, UUID.randomUUID(), null, Map.of("name", "Haushalt")));

        // lastSeq 0 means: nothing seen yet -- not: something missed.
        device.setLastSeq(0);
        var response = device.pullOnce();

        assertThat(response.get("resyncRequired")).isEqualTo(false);
        assertThat((java.util.List<?>) response.get("changes")).hasSize(1);
    }

    @Test
    void thePullReportsTheDevicePositionToTheDeviceList() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);
        device.push(SyncClient.mutation(LIST, UUID.randomUUID(), null, Map.of("name", "Haushalt")));
        device.pullAll();
        long confirmed = device.lastSeq();
        // Something new, then one more pull: what gets reported is what the device has
        // *confirmed* -- the position it asked from -- not the one in this response.
        // Recording that would mean assuming the response arrives, and on the road that
        // is exactly the question.
        device.push(SyncClient.mutation(LIST, UUID.randomUUID(), null, Map.of("name", "Garten")));
        device.pullOnce();
        assertThat(device.lastSeq()).isGreaterThan(confirmed);

        // Without last_sync_seq and pending_count there would be no sync state in the
        // device list -- and that is exactly what the design asks for.
        rest.get()
                .uri("/api/v1/devices")
                .headers(session.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.devices[0].lastSyncSeq")
                .isEqualTo((int) confirmed)
                .jsonPath("$.devices[0].pendingCount")
                .isEqualTo(0);
    }


    /** A pull records the position of the device the token belongs to, whatever the body says. */
    @Test
    void aPullCannotMoveAnotherDevice() {
        var anna = Family.setUp(rest);
        var laptop = Family.login(rest, "anna", "geheim-genug", "Laptop");
        var phone = new SyncClient(rest, anna);
        phone.push(SyncClient.mutation(LIST, UUID.randomUUID(), null, Map.of("name", "Haushalt")));
        phone.pullAll();
        phone.pullAll();
        long phonePosition = phone.lastSeq();

        rest.post()
                .uri("/api/v1/sync/pull")
                .headers(laptop.auth())
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                .body(Map.of("deviceId", anna.deviceId().toString(), "lastSeq", 0, "pendingCount", 7))
                .exchange()
                .expectStatus()
                .isOk();

        rest.get()
                .uri("/api/v1/devices")
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.devices[?(@.id=='" + anna.deviceId() + "')].lastSyncSeq")
                .isEqualTo((int) phonePosition)
                .jsonPath("$.devices[?(@.id=='" + anna.deviceId() + "')].pendingCount")
                .isEqualTo(0);
    }

    /**
     * A member who sees nothing of what the others write still moves along: otherwise
     * their position stood still until retention cleaned past it and forced a resync.
     */
    @Test
    void aPullWithNothingVisibleStillAdvances() {
        var anna = Family.setUp(rest);
        var annasDevice = new SyncClient(rest, anna);
        var invitation = rest.post()
                .uri("/api/v1/invitations")
                .headers(anna.auth())
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                .body(Map.of("validity", "HOURS_24"))
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        var ben = Family.toSession(rest.post()
                .uri("/api/v1/invitations/" + invitation.get("code") + "/redeem")
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "displayName", "Ben",
                        "username", "ben",
                        "password", "bens-langes-passwort",
                        "device", Map.of("deviceName", "Tablet", "platform", "ANDROID")))
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody());
        var bensDevice = new SyncClient(rest, ben);
        bensDevice.pullAll();
        long before = bensDevice.lastSeq();

        annasDevice.push(SyncClient.mutation(LIST, UUID.randomUUID(), null, Map.of("name", "Privat")));
        var page = bensDevice.pullOnce();

        assertThat((java.util.List<?>) page.get("changes")).isEmpty();
        assertThat(bensDevice.lastSeq()).isGreaterThan(before);
    }
}
