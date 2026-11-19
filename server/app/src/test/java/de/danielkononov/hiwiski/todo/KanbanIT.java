package de.danielkononov.hiwiski.todo;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * Kanban boards: what the server accepts from a board, and what it does
 * not — whatever the app would have offered.
 */
@IntegrationTest
class KanbanIT {

    private static final String LIST = "TODO_LIST";
    private static final String TODO = "TODO";

    @Autowired RestTestClient rest;

    private Family.Session anna;
    private SyncClient device;

    private final UUID todoColumn = UUID.randomUUID();
    private final UUID doingColumn = UUID.randomUUID();
    private final UUID doneColumn = UUID.randomUUID();

    @BeforeEach
    void signIn() {
        anna = Family.setUp(rest);
        device = new SyncClient(rest, anna);
    }

    private static Map<String, Object> column(UUID id, String name, boolean done) {
        return Map.of("id", id.toString(), "name", name, "colorToken", "BLUE", "done", done);
    }

    private List<Map<String, Object>> threeColumns() {
        return List.of(
                column(todoColumn, "Offen", false),
                column(doingColumn, "In Arbeit", false),
                column(doneColumn, "Erledigt", true));
    }

    private Map<String, Object> pushOne(Map<String, Object> mutation) {
        return device.push(mutation).getFirst();
    }

    private static long version(Map<String, Object> result) {
        return ((Number) result.get("version")).longValue();
    }

    private static void assertRejected(Map<String, Object> result, String code) {
        assertThat(result.get("status")).isEqualTo("rejected");
        assertThat(result.get("code")).isEqualTo(code);
    }

    @Test
    void aBoardNeedsTwoToEightColumnsADoneColumnAndAnOpenOne() {
        var single = pushOne(SyncClient.mutation(
                LIST,
                UUID.randomUUID(),
                null,
                Map.of("name", "Umzug", "kind", "KANBAN", "columns", List.of(column(doneColumn, "Erledigt", true)))));
        // Every column done: nowhere for a card to be open.
        var twoDone = pushOne(SyncClient.mutation(
                LIST,
                UUID.randomUUID(),
                null,
                Map.of(
                        "name",
                        "Umzug",
                        "kind",
                        "KANBAN",
                        "columns",
                        List.of(column(todoColumn, "Offen", true), column(doneColumn, "Erledigt", true)))));
        var nine = pushOne(SyncClient.mutation(
                LIST,
                UUID.randomUUID(),
                null,
                Map.of(
                        "name",
                        "Umzug",
                        "kind",
                        "KANBAN",
                        "columns",
                        java.util.stream.IntStream.range(0, 9)
                                .mapToObj(i -> column(UUID.randomUUID(), "Spalte " + i, i == 8))
                                .toList())));
        var none = pushOne(SyncClient.mutation(
                LIST, UUID.randomUUID(), null, Map.of("name", "Umzug", "kind", "KANBAN")));

        for (var result : List.of(single, twoDone, nine, none)) {
            assertRejected(result, "todo.kanban_columns_invalid");
        }

        var valid = pushOne(SyncClient.mutation(
                LIST, UUID.randomUUID(), null, Map.of("name", "Umzug", "kind", "KANBAN", "columns", threeColumns())));
        assertThat(valid.get("status")).isEqualTo("applied");

        var twoDoneOfThree = pushOne(SyncClient.mutation(
                LIST,
                UUID.randomUUID(),
                null,
                Map.of(
                        "name",
                        "Umzug",
                        "kind",
                        "KANBAN",
                        "columns",
                        List.of(
                                column(todoColumn, "Offen", false),
                                column(doneColumn, "Erledigt", true),
                                column(UUID.randomUUID(), "Archiv", true)))));
        assertThat(twoDoneOfThree.get("status")).isEqualTo("applied");
    }

    @Test
    void aTaskListBecomesABoardButNothingElseChangesItsKind() {
        UUID listId = UUID.randomUUID();
        long version = version(pushOne(SyncClient.mutation(LIST, listId, null, Map.of("name", "Renovierung"))));

        // A board without columns is no board.
        assertRejected(
                pushOne(SyncClient.mutation(LIST, listId, version, Map.of("kind", "KANBAN"))),
                "todo.kanban_columns_invalid");

        var converted = pushOne(
                SyncClient.mutation(LIST, listId, version, Map.of("kind", "KANBAN", "columns", threeColumns())));
        assertThat(converted.get("status")).isEqualTo("applied");

        // Not back again …
        assertRejected(
                pushOne(SyncClient.mutation(LIST, listId, version(converted), Map.of("kind", "STANDARD"))),
                "todo.kind_locked");
        // … and its columns stay valid on every later change.
        assertRejected(
                pushOne(SyncClient.mutation(
                        LIST,
                        listId,
                        version(converted),
                        Map.of("columns", List.of(column(doneColumn, "Erledigt", true))))),
                "todo.kanban_columns_invalid");

        // A shopping list does not become a board.
        UUID shoppingId = UUID.randomUUID();
        long shoppingVersion = version(
                pushOne(SyncClient.mutation(LIST, shoppingId, null, Map.of("name", "Einkauf", "kind", "SHOPPING"))));
        assertRejected(
                pushOne(SyncClient.mutation(
                        LIST, shoppingId, shoppingVersion, Map.of("kind", "KANBAN", "columns", threeColumns()))),
                "todo.kind_locked");
    }

    /** A kind no client knows could never become a board -- and a number is no kind. */
    @Test
    void anUnknownKindIsRefused() {
        for (Object kind : List.of("BOARD", "kanban", 1)) {
            assertRejected(
                    pushOne(SyncClient.mutation(LIST, UUID.randomUUID(), null, Map.of("name", "Neu", "kind", kind))),
                    "todo.kind_invalid");
        }
    }

    /** A task list with repeating tasks does not become a board. */
    @Test
    void aListWithRepeatsDoesNotBecomeABoard() {
        UUID listId = UUID.randomUUID();
        long version = version(pushOne(SyncClient.mutation(LIST, listId, null, Map.of("name", "Putzplan"))));
        device.push(SyncClient.withContainer(
                SyncClient.mutation("TODO", UUID.randomUUID(), null, Map.of("title", "Bad", "rrule", "FREQ=WEEKLY")),
                LIST,
                listId));

        assertRejected(
                pushOne(SyncClient.mutation(LIST, listId, version, Map.of("kind", "KANBAN", "columns", threeColumns()))),
                "todo.kanban_no_repeat");
    }

    @Test
    void aCardOnABoardDoesNotRepeat() {
        UUID boardId = UUID.randomUUID();
        device.push(SyncClient.mutation(
                LIST, boardId, null, Map.of("name", "Umzug", "kind", "KANBAN", "columns", threeColumns())));

        var repeating = pushOne(SyncClient.withContainer(
                SyncClient.mutation(TODO, UUID.randomUUID(), null, Map.of("title", "Müll", "rrule", "FREQ=WEEKLY")),
                LIST,
                boardId));
        assertRejected(repeating, "todo.kanban_no_repeat");

        var card = pushOne(SyncClient.withContainer(
                SyncClient.mutation(
                        TODO,
                        UUID.randomUUID(),
                        null,
                        Map.of("title", "Kartons", "status", "OPEN", "columnId", doingColumn.toString())),
                LIST,
                boardId));
        assertThat(card.get("status")).isEqualTo("applied");

        // On a task list a repeat is fine, as ever.
        UUID listId = UUID.randomUUID();
        device.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Haushalt")));
        var weekly = pushOne(SyncClient.withContainer(
                SyncClient.mutation(TODO, UUID.randomUUID(), null, Map.of("title", "Müll", "rrule", "FREQ=WEEKLY")),
                LIST,
                listId));
        assertThat(weekly.get("status")).isEqualTo("applied");
    }

    /** "Changed: Column" did not say where the card went; the history names the column. */
    @Test
    void theHistorySaysWhichColumnACardWentTo() {
        UUID boardId = UUID.randomUUID();
        UUID cardId = UUID.randomUUID();
        device.push(SyncClient.mutation(
                LIST, boardId, null, Map.of("name", "Umzug", "kind", "KANBAN", "columns", threeColumns())));
        long version = version(pushOne(SyncClient.withContainer(
                SyncClient.mutation(
                        TODO, cardId, null, Map.of("title", "Kartons", "status", "OPEN", "columnId", todoColumn.toString())),
                LIST,
                boardId)));
        pushOne(SyncClient.mutation(TODO, cardId, version, Map.of("columnId", doingColumn.toString())));

        var history = rest.get()
                .uri("/api/v1/history/" + TODO + "/" + cardId)
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();

        @SuppressWarnings("unchecked")
        var entries = (List<Map<String, Object>>) history.get("entries");
        assertThat(entries).extracting(entry -> entry.get("column"))
                .describedAs("moved to Doing, created in To do")
                .containsExactly("In Arbeit", "Offen");
    }

    /** On a board the column is the progress: *check off* moves cards, not more. */
    @Test
    void checkOffMovesACardToAnotherColumnButDoesNotReorder() {
        UUID boardId = UUID.randomUUID();
        UUID cardId = UUID.randomUUID();
        device.push(SyncClient.mutation(
                LIST, boardId, null, Map.of("name", "Umzug", "kind", "KANBAN", "columns", threeColumns())));
        long cardVersion = version(pushOne(SyncClient.withContainer(
                SyncClient.mutation(TODO, cardId, null, Map.of("title", "Kartons", "status", "OPEN")),
                LIST,
                boardId)));

        var ben = invite("ben");
        rest.put()
                .uri("/api/v1/items/" + LIST + "/" + boardId + "/shares")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("shares", List.of(Map.of(
                        "subjectType", "MEMBER", "subjectId", ben.memberId().toString(), "level", "CHECK"))))
                .exchange()
                .expectStatus()
                .isOk();
        var bensDevice = new SyncClient(rest, ben);

        var moved = bensDevice
                .push(SyncClient.withContainer(
                        SyncClient.mutation(
                                TODO,
                                cardId,
                                cardVersion,
                                Map.of("columnId", doneColumn.toString(), "status", "DONE")),
                        LIST,
                        boardId))
                .getFirst();
        assertThat(moved.get("status")).isEqualTo("applied");

        Map<String, Object> reorder = new HashMap<>();
        reorder.put("position", 3);
        var reordered = bensDevice
                .push(SyncClient.withContainer(
                        SyncClient.mutation(TODO, cardId, version(moved), reorder), LIST, boardId))
                .getFirst();
        assertRejected(reordered, "access.field_not_allowed");
    }

    private Family.Session invite(String username) {
        var invitation = rest.post()
                .uri("/api/v1/invitations")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("validity", "HOURS_24"))
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        var signedIn = rest.post()
                .uri("/api/v1/invitations/" + invitation.get("code") + "/redeem")
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "displayName", "Ben",
                        "username", username,
                        "password", "bens-langes-passwort",
                        "device", Map.of("deviceName", "Bens Tablet", "platform", "ANDROID")))
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        return Family.toSession(signedIn);
    }
}
