package de.danielkononov.hiwiski.tag;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.client.RestTestClient;

/** Tags with their own sharing and assignment to lists. */
@IntegrationTest
class TagIT {

    @Autowired RestTestClient rest;

    private Family.Session anna;
    private Family.Session ben;
    private SyncClient annasDevice;
    private SyncClient bensDevice;

    @BeforeEach
    void family() {
        anna = Family.setUp(rest);
        var invitation = rest.post()
                .uri("/api/v1/invitations")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("validity", "HOURS_24"))
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        ben = Family.toSession(rest.post()
                .uri("/api/v1/invitations/" + invitation.get("code") + "/redeem")
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "displayName", "Ben",
                        "username", "ben",
                        "password", "bens-langes-passwort",
                        "device", Map.of("deviceName", "Bens Tablet", "platform", "ANDROID")))
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody());
        annasDevice = new SyncClient(rest, anna);
        bensDevice = new SyncClient(rest, ben);
    }

    @Test
    @SuppressWarnings({"unchecked", "rawtypes"})
    void anOwnTagStaysPrivateAndIsAttachedToTheItem() {
        UUID gift = UUID.randomUUID();
        UUID list = UUID.randomUUID();
        var result = annasDevice.push(
                SyncClient.mutation("TAG", gift, null, Map.of("name", "Geschenk", "colorToken", "PINK")),
                SyncClient.mutation(
                        "TODO_LIST", list, null, Map.of("name", "Ideen", "tags", List.of(gift.toString()))));
        assertThat(result).allMatch(r -> "applied".equals(r.get("status")));

        var annas = annasDevice.pullAll();
        assertThat(annas).anyMatch(c -> list.toString().equals(c.get("entityId"))
                && List.of(gift.toString()).equals(((Map) c.get("fields")).get("tags")));

        // "Geschenk fuer Mama" (gift for Mom) is none of Ben's business.
        assertThat(bensDevice.pullAll()).noneMatch(c -> "TAG".equals(c.get("entityType")));
    }

    @Test
    void anotherDeviceGetsTheNumberInThePull() {
        // The number was in the envelope's contract but was never filled: only the creating
        // device knew it from the push response, every other one showed "—".
        UUID list = UUID.randomUUID();
        UUID task = UUID.randomUUID();
        annasDevice.push(SyncClient.mutation(
                "TODO_LIST", list, null, Map.of("name", "Keller", "assignees", List.of(ben.memberId().toString()))));
        var result = annasDevice.push(SyncClient.withContainer(
                SyncClient.mutation("TODO", task, null, Map.of("title", "Regal", "status", "OPEN")),
                "TODO_LIST",
                list));
        Object key = result.getFirst().get("entityKey");
        assertThat(key).isNotNull();

        assertThat(bensDevice.pullAll())
                .anyMatch(c -> task.toString().equals(c.get("entityId")) && key.equals(c.get("entityKey")));
    }

    @Test
    @SuppressWarnings("unchecked")
    void assigneesMayCreateInTheList() {
        UUID list = UUID.randomUUID();
        annasDevice.push(SyncClient.mutation(
                "TODO_LIST", list, null, Map.of("name", "Keller", "assignees", List.of(ben.memberId().toString()))));

        // Ben sees the list without it having been shared with him ...
        assertThat(bensDevice.pullAll()).anyMatch(c -> list.toString().equals(c.get("entityId")));

        // ... and may create in it: being assigned to a list means writing along.
        var result = bensDevice.push(SyncClient.withContainer(
                SyncClient.mutation("TODO", UUID.randomUUID(), null, Map.of("title", "Regal", "status", "OPEN")),
                "TODO_LIST",
                list));
        assertThat(result.getFirst().get("status")).isEqualTo("applied");
    }
}
