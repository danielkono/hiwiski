package de.danielkononov.hiwiski.wiki;

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

/**
 * Comments on all items.
 *
 * <p>The sync type was missing until now: every comment came back with
 * {@code sync.unknown_entity_type}. Whoever may read may comment; whoever cannot see the
 * parent item cannot see the comment either.
 */
@IntegrationTest
class CommentIT {

    private static final String LIST = "TODO_LIST";
    private static final String COMMENT = "COMMENT";

    @Autowired RestTestClient rest;

    private Family.Session anna;
    private Family.Session ben;
    private SyncClient annasDevice;
    private SyncClient bensDevice;
    private UUID listId;

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

        listId = UUID.randomUUID();
        annasDevice.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Haushalt")));
    }

    private Map<String, Object> comment(UUID id, String text) {
        return SyncClient.withContainer(
                SyncClient.mutation(
                        COMMENT,
                        id,
                        null,
                        Map.of("itemType", LIST, "itemId", listId.toString(), "body", text)),
                LIST,
                listId);
    }

    private void share(String level) {
        rest.put()
                .uri("/api/v1/items/" + LIST + "/" + listId + "/shares")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("shares", List.of(Map.of(
                        "subjectType", "MEMBER",
                        "subjectId", ben.memberId().toString(),
                        "level", level))))
                .exchange()
                .expectStatus()
                .isOk();
    }

    @Test
    void theOwnerCommentsOnHisList() {
        var result = annasDevice.push(comment(UUID.randomUUID(), "Tonne ist draußen"));
        assertThat(result.getFirst().get("status")).isEqualTo("applied");
    }

    @Test
    void whoeverMayReadCommentsAndSeesTheComments() {
        UUID fromAnna = UUID.randomUUID();
        annasDevice.push(comment(fromAnna, "Wer macht das?"));
        share("READ");

        UUID fromBen = UUID.randomUUID();
        var result = bensDevice.push(comment(fromBen, "Ich"));
        assertThat(result.getFirst().get("status")).isEqualTo("applied");

        // The comment inherits the share from its parent item: Ben sees Anna's too.
        bensDevice.setLastSeq(0);
        var changes = bensDevice.pullAll();
        assertThat(changes).anyMatch(change -> fromAnna.toString().equals(change.get("entityId")));
        // And knows whose it is: otherwise his app would show Anna's comment as his own.
        assertThat(changes)
                .filteredOn(change -> fromAnna.toString().equals(change.get("entityId"))
                        && "upsert".equals(change.get("op")))
                .isNotEmpty()
                .allMatch(change -> anna.memberId().toString().equals(change.get("ownerId")));
        assertThat(bensDevice.pullSnapshot(500))
                .filteredOn(change -> fromAnna.toString().equals(change.get("entityId")))
                .singleElement()
                .satisfies(change -> assertThat(change.get("ownerId")).isEqualTo(anna.memberId().toString()));
    }

    @Test
    void whoeverCannotSeeTheParentCannotComment() {
        var result = bensDevice.push(comment(UUID.randomUUID(), "Hallo?"));
        assertThat(result.getFirst().get("status")).isNotEqualTo("applied");

        annasDevice.push(comment(UUID.randomUUID(), "Privat"));
        assertThat(bensDevice.pullAll())
                .noneMatch(change -> COMMENT.equals(change.get("entityType")));
    }

    private static long version(List<Map<String, Object>> results) {
        return ((Number) results.getFirst().get("version")).longValue();
    }

    /** Access to the carrier lets everyone comment -- not rewrite or remove what others said. */
    @Test
    void someoneElsesCommentStaysEvenWithWriteAccessToTheList() {
        UUID fromAnna = UUID.randomUUID();
        long version = version(annasDevice.push(comment(fromAnna, "Wer macht das?")));
        share("WRITE");

        var edit = bensDevice.push(SyncClient.mutation(COMMENT, fromAnna, version, Map.of("body", "Niemand")));
        assertThat(edit.getFirst().get("status")).isEqualTo("rejected");

        var delete = bensDevice.push(SyncClient.deletion(COMMENT, fromAnna, version));
        assertThat(delete.getFirst().get("status")).isEqualTo("rejected");
        assertThat(delete.getFirst().get("code")).isEqualTo("access.denied");
    }

    @Test
    void oneDeletesOnesOwnComment() {
        share("READ");
        UUID fromBen = UUID.randomUUID();
        long version = version(bensDevice.push(comment(fromBen, "Ich")));

        var delete = bensDevice.push(SyncClient.deletion(COMMENT, fromBen, version));
        assertThat(delete.getFirst().get("status")).isEqualTo("applied");
    }

    /**
     * The carrier is the item the access check approved: a comment cannot name another
     * one in its fields, neither when it is written nor later.
     */
    @Test
    void aCommentStaysOnTheItemItWasWrittenOn() {
        UUID annasPrivate = UUID.randomUUID();
        annasDevice.push(SyncClient.mutation(LIST, annasPrivate, null, Map.of("name", "Geschenke")));
        share("READ");

        UUID sneaked = UUID.randomUUID();
        var create = bensDevice.push(SyncClient.withContainer(
                SyncClient.mutation(
                        COMMENT,
                        sneaked,
                        null,
                        Map.of("itemType", LIST, "itemId", annasPrivate.toString(), "body", "Gesehen")),
                LIST,
                listId));
        assertThat(create.getFirst().get("status")).isEqualTo("rejected");

        UUID own = UUID.randomUUID();
        long version = version(bensDevice.push(comment(own, "Ich")));
        var move = bensDevice.push(
                SyncClient.mutation(COMMENT, own, version, Map.of("itemId", annasPrivate.toString())));
        assertThat(move.getFirst().get("status")).isEqualTo("rejected");

        assertThat(annasDevice.pullAll())
                .noneMatch(change -> sneaked.toString().equals(change.get("entityId"))
                        && "upsert".equals(change.get("op")));
        var fieldsOfOwn = bensDevice.pullSnapshot(500).stream()
                .filter(change -> own.toString().equals(change.get("entityId")))
                .findFirst()
                .orElseThrow();
        assertThat(fieldsOfOwn.toString()).contains(listId.toString()).doesNotContain(annasPrivate.toString());
    }

    @Test
    void anEditMayRepeatTheCarrier() {
        UUID own = UUID.randomUUID();
        long version = version(annasDevice.push(comment(own, "Erst")));

        var edit = annasDevice.push(SyncClient.mutation(
                COMMENT, own, version, Map.of("itemType", LIST, "itemId", listId.toString(), "body", "Dann")));

        assertThat(edit.getFirst().get("status")).isEqualTo("applied");
    }
}
