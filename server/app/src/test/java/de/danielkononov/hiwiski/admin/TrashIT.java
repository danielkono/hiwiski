package de.danielkononov.hiwiski.admin;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * The trash.
 *
 * <p>Forgotten in the design and mandatory anyway: without it every disappearance is
 * final, and for a family app that is the wrong promise.
 */
@IntegrationTest
class TrashIT {

    private static final String LIST = "TODO_LIST";
    private static final String TODO = "TODO";

    @Autowired RestTestClient rest;

    @Test
    void deletedItemsAppearInTheTrashAndComeBack() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);

        UUID listId = UUID.randomUUID();
        UUID todoId = UUID.randomUUID();
        device.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Haushalt")));
        var todo = device.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, todoId, null, Map.of("title", "Müll rausbringen")), LIST, listId));
        long version = ((Number) todo.get(0).get("version")).longValue();

        device.push(SyncClient.deletion(TODO, todoId, version));
        // The device has pulled the delete and dropped the task.
        device.pullAll();

        rest.get()
                .uri("/api/v1/trash")
                .headers(session.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.entries.length()")
                .isEqualTo(1)
                // Type icon, title, mono number, "28 days left". Without
                // the title nobody would look for anything here.
                .jsonPath("$.entries[0].title")
                .isEqualTo("Müll rausbringen")
                .jsonPath("$.entries[0].entityKey")
                .isEqualTo("TD-1")
                .jsonPath("$.entries[0].restorable")
                .isEqualTo(true);

        rest.post()
                .uri("/api/v1/trash/" + TODO + "/" + todoId + "/restore")
                .headers(session.auth())
                .exchange()
                .expectStatus()
                .isNoContent();

        rest.get()
                .uri("/api/v1/trash")
                .headers(session.auth())
                .exchange()
                .expectBody()
                .jsonPath("$.entries.length()")
                .isEqualTo(0);

        // And it is back -- for a device that only pulls what is new, with every field,
        // since it has nothing left to merge them into. Its share came along: deleting
        // never touched it.
        var changes = device.pullAll();
        assertThat(changes)
                .filteredOn(change -> todoId.toString().equals(change.get("entityId")))
                .singleElement()
                .satisfies(change -> {
                    assertThat(change.get("op")).isEqualTo("upsert");
                    assertThat(change.get("entityKey")).isEqualTo("TD-1");
                    assertThat((Map<String, Object>) change.get("fields"))
                            .containsEntry("title", "Müll rausbringen")
                            .containsKey("status");
                });
    }

    @Test
    void withoutAContainerRestoreAsksForATarget() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);

        UUID listId = UUID.randomUUID();
        UUID todoId = UUID.randomUUID();
        var list = device.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Haushalt")));
        var todo = device.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, todoId, null, Map.of("title", "Müll")), LIST, listId));

        device.push(SyncClient.deletion(TODO, todoId, ((Number) todo.get(0).get("version")).longValue()));
        device.push(SyncClient.deletion(LIST, listId, ((Number) list.get(0).get("version")).longValue()));

        rest.get()
                .uri("/api/v1/trash?itemType=" + TODO)
                .headers(session.auth())
                .exchange()
                .expectBody()
                // If its container is gone by now, it goes into a "No location" list and
                // asks for a target.
                .jsonPath("$.entries[0].restorable")
                .isEqualTo(false);

        rest.post()
                .uri("/api/v1/trash/" + TODO + "/" + todoId + "/restore")
                .headers(session.auth())
                .exchange()
                .expectStatus()
                .isBadRequest()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("trash.container_gone");

        // The target the UI asked for: another list. The task comes back there, on every
        // device.
        UUID otherList = UUID.randomUUID();
        device.push(SyncClient.mutation(LIST, otherList, null, Map.of("name", "Garten")));
        device.pullAll();

        rest.post()
                .uri("/api/v1/trash/" + TODO + "/" + todoId + "/restore")
                .headers(session.auth())
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                .body(Map.of("targetContainerId", otherList.toString()))
                .exchange()
                .expectStatus()
                .isNoContent();

        assertThat(device.pullAll())
                .filteredOn(change -> todoId.toString().equals(change.get("entityId")))
                .singleElement()
                .satisfies(change -> {
                    assertThat(change.get("op")).isEqualTo("upsert");
                    assertThat(change.get("containerId")).isEqualTo(otherList.toString());
                });
    }

    /** A target is a container like any other: the restorer needs write access to it. */
    @Test
    void theTargetHasToBeWritable() {
        var anna = Family.setUp(rest);
        var annasDevice = new SyncClient(rest, anna);
        var ben = invite(anna);
        var bensDevice = new SyncClient(rest, ben);

        UUID annasList = UUID.randomUUID();
        annasDevice.push(SyncClient.mutation(LIST, annasList, null, Map.of("name", "Annas Liste")));

        UUID bensList = UUID.randomUUID();
        UUID todoId = UUID.randomUUID();
        var list = bensDevice.push(SyncClient.mutation(LIST, bensList, null, Map.of("name", "Bens Liste")));
        var todo = bensDevice.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, todoId, null, Map.of("title", "Rasen")), LIST, bensList));
        bensDevice.push(SyncClient.deletion(TODO, todoId, ((Number) todo.get(0).get("version")).longValue()));
        bensDevice.push(SyncClient.deletion(LIST, bensList, ((Number) list.get(0).get("version")).longValue()));

        for (UUID target : List.of(annasList, bensList, UUID.randomUUID())) {
            rest.post()
                    .uri("/api/v1/trash/" + TODO + "/" + todoId + "/restore")
                    .headers(ben.auth())
                    .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                    .body(Map.of("targetContainerId", target.toString()))
                    .exchange()
                    .expectStatus()
                    .isNotFound();
        }
    }

    /** A top-level page has no parent, which is not the same as a lost one. */
    /** A page's container is a page — the same table, which the trash query must keep apart. */
    @Test
    void aSubpageWhoseParentIsGoneAsksForATarget() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);

        UUID parentId = UUID.randomUUID();
        UUID childId = UUID.randomUUID();
        var parent = device.push(SyncClient.mutation(
                "WIKI_PAGE", parentId, null, Map.of("title", "Haus", "kind", "PAGE", "content", "")));
        var child = device.push(SyncClient.withContainer(
                SyncClient.mutation(
                        "WIKI_PAGE", childId, null, Map.of("title", "Heizung", "kind", "PAGE", "content", "")),
                "WIKI_PAGE",
                parentId));
        device.push(SyncClient.deletion("WIKI_PAGE", childId, ((Number) child.get(0).get("version")).longValue()));

        rest.get()
                .uri("/api/v1/trash?itemType=WIKI_PAGE")
                .headers(session.auth())
                .exchange()
                .expectBody()
                .jsonPath("$.entries[?(@.title=='Heizung')].restorable")
                .isEqualTo(true);

        device.push(SyncClient.deletion("WIKI_PAGE", parentId, ((Number) parent.get(0).get("version")).longValue()));

        rest.get()
                .uri("/api/v1/trash?itemType=WIKI_PAGE")
                .headers(session.auth())
                .exchange()
                .expectBody()
                .jsonPath("$.entries[?(@.title=='Heizung')].restorable")
                .isEqualTo(false);
    }

    @Test
    void aTopLevelPageComesBack() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);

        UUID pageId = UUID.randomUUID();
        var page = device.push(SyncClient.mutation(
                "WIKI_PAGE", pageId, null, Map.of("title", "Rezepte", "kind", "PAGE", "content", "")));
        device.push(SyncClient.deletion("WIKI_PAGE", pageId, ((Number) page.get(0).get("version")).longValue()));

        rest.get()
                .uri("/api/v1/trash?itemType=WIKI_PAGE")
                .headers(session.auth())
                .exchange()
                .expectBody()
                .jsonPath("$.entries[0].restorable")
                .isEqualTo(true);

        rest.post()
                .uri("/api/v1/trash/WIKI_PAGE/" + pageId + "/restore")
                .headers(session.auth())
                .exchange()
                .expectStatus()
                .isNoContent();
    }

    @Test
    void itemsDeletedByOthersAreNotInMyTrash() {
        var anna = Family.setUp(rest);
        var annasDevice = new SyncClient(rest, anna);
        var ben = invite(anna);

        UUID listId = UUID.randomUUID();
        var list = annasDevice.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Annas Liste")));
        annasDevice.push(SyncClient.deletion(LIST, listId, ((Number) list.get(0).get("version")).longValue()));

        // The administrator does not see other members' content -- not in the trash
        // either. Here Ben is not an administrator, but the rule applies
        // in both directions.
        rest.get()
                .uri("/api/v1/trash")
                .headers(ben.auth())
                .exchange()
                .expectBody()
                .jsonPath("$.entries.length()")
                .isEqualTo(0);
    }

    /**
     * Everyone is told how long the trash keeps things. It was only in the
     * administrator's settings: everyone else read the default.
     */
    @Test
    void everyMemberLearnsTheRetention() {
        var anna = Family.setUp(rest);
        var ben = invite(anna);
        rest.put()
                .uri("/api/v1/admin/settings")
                .headers(anna.auth())
                .body(Map.of("trashRetentionDays", 7))
                .exchange()
                .expectStatus()
                .isOk();

        rest.get()
                .uri("/api/v1/trash")
                .headers(ben.auth())
                .exchange()
                .expectBody()
                .jsonPath("$.retentionDays")
                .isEqualTo(7);
    }

    /** What is not in one's trash cannot be restored from it either, ID or not. */
    @Test
    void onlyWhatIsInMyTrashComesBack() {
        var anna = Family.setUp(rest);
        var annasDevice = new SyncClient(rest, anna);
        var ben = invite(anna);

        UUID listId = UUID.randomUUID();
        var list = annasDevice.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Annas Liste")));
        annasDevice.push(SyncClient.deletion(LIST, listId, ((Number) list.get(0).get("version")).longValue()));

        rest.post()
                .uri("/api/v1/trash/" + LIST + "/" + listId + "/restore")
                .headers(ben.auth())
                .exchange()
                .expectStatus()
                .isNotFound();

        rest.get()
                .uri("/api/v1/trash")
                .headers(anna.auth())
                .exchange()
                .expectBody()
                .jsonPath("$.entries.length()")
                .isEqualTo(1);
    }

    private Family.Session invite(Family.Session anna) {
        var invitation = rest.post()
                .uri("/api/v1/invitations")
                .headers(anna.auth())
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                .body(Map.of("validity", "HOURS_24"))
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        var bensSignIn = rest.post()
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
                .getResponseBody();
        return Family.toSession(bensSignIn);
    }
}
