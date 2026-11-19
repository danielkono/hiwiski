package de.danielkononov.hiwiski.todo;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.jooq.DSLContext;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * What a home screen widget shows of a list while the app is closed: the open entries in
 * the list's order, the counts, and on a board the cards standing in one column — derived
 * as the app derives it.
 */
@IntegrationTest
@SuppressWarnings("unchecked")
class ListSummaryIT {

    private static final String LIST = "TODO_LIST";
    private static final String TODO = "TODO";

    @Autowired RestTestClient rest;
    @Autowired DSLContext db;

    private Family.Session anna;
    private SyncClient phone;

    @BeforeEach
    void aFamily() {
        anna = Family.setUp(rest);
        phone = new SyncClient(rest, anna);
    }

    @Test
    void theOpenEntriesInTheListsOrderAndTheCounts() {
        UUID groceries = list(Map.of("name", "Groceries", "kind", "SHOPPING", "colorToken", "OCHRE"));
        todo(groceries, Map.of("title", "Milk", "status", "OPEN", "position", 2000, "amount", 2, "unit", "l"));
        todo(groceries, Map.of("title", "Bread", "status", "OPEN", "position", 1000));
        todo(groceries, Map.of("title", "Apples", "status", "DONE", "position", 500));

        var summary = summary(anna, groceries, Map.of(), HttpStatus.OK);

        assertThat(summary)
                .containsEntry("name", "Groceries")
                .containsEntry("kind", "SHOPPING")
                .containsEntry("colorToken", "OCHRE")
                .containsEntry("openCount", 2)
                .containsEntry("doneCount", 1)
                .containsEntry("truncated", false)
                .containsEntry("archived", false);
        var items = (List<Map<String, Object>>) summary.get("items");
        assertThat(items).extracting(i -> i.get("title")).containsExactly("Bread", "Milk");
        assertThat(items.get(1)).containsEntry("unit", "l").containsEntry("done", false);
        assertThat(((Number) items.get(1).get("amount")).intValue()).isEqualTo(2);
        assertThat(((Number) summary.get("position")).longValue()).isPositive();
    }

    @Test
    void aColumnShowsTheCardsStandingInIt() {
        UUID open = UUID.randomUUID();
        UUID doing = UUID.randomUUID();
        UUID done = UUID.randomUUID();
        UUID board = list(Map.of(
                "name", "Household",
                "kind", "KANBAN",
                "columns", List.of(
                        Map.of("id", open.toString(), "name", "To do", "done", false),
                        Map.of("id", doing.toString(), "name", "Doing", "done", false, "colorToken", "BLUE"),
                        Map.of("id", done.toString(), "name", "Done", "done", true))));
        todo(board, Map.of("title", "Paint", "status", "OPEN", "columnId", doing.toString(), "position", 1000));
        // Ticked off elsewhere: its column still says "Doing", but a done card stands in
        // the done column -- in the app as here.
        todo(board, Map.of("title", "Shelf", "status", "DONE", "columnId", doing.toString(), "position", 2000));
        todo(board, Map.of("title", "Lamp", "status", "OPEN", "columnId", open.toString(), "position", 3000));

        var doingNow = summary(anna, board, Map.of("columnId", doing.toString()), HttpStatus.OK);
        var finished = summary(anna, board, Map.of("columnId", done.toString()), HttpStatus.OK);

        assertThat((List<Map<String, Object>>) doingNow.get("items"))
                .extracting(i -> i.get("title"))
                .containsExactly("Paint");
        assertThat((Map<String, Object>) doingNow.get("column"))
                .containsEntry("id", doing.toString())
                .containsEntry("name", "Doing")
                .containsEntry("colorToken", "BLUE")
                .containsEntry("done", false)
                .containsEntry("count", 1);
        assertThat((List<Map<String, Object>>) finished.get("items"))
                .extracting(i -> i.get("title"))
                .containsExactly("Shelf");
        assertThat(doingNow).containsEntry("openCount", 2).containsEntry("doneCount", 1);
    }

    @Test
    void aColumnTheBoardNoLongerHasAnswersLikeNoColumn() {
        UUID open = UUID.randomUUID();
        UUID done = UUID.randomUUID();
        UUID board = list(Map.of(
                "name", "Household",
                "kind", "KANBAN",
                "columns", List.of(
                        Map.of("id", open.toString(), "name", "To do", "done", false),
                        Map.of("id", done.toString(), "name", "Done", "done", true))));
        todo(board, Map.of("title", "Paint", "status", "OPEN", "columnId", open.toString()));

        var summary = summary(anna, board, Map.of("columnId", UUID.randomUUID().toString()), HttpStatus.OK);

        assertThat(summary.get("column")).isNull();
        assertThat((List<Map<String, Object>>) summary.get("items"))
                .extracting(i -> i.get("title"))
                .containsExactly("Paint");
    }

    @Test
    void aListNotSharedAnswersLikeAMissingOne() {
        UUID mine = list(Map.of("name", "Presents", "kind", "STANDARD"));
        var ben = invite("Ben", "ben");

        var hidden = summary(ben, mine, Map.of(), HttpStatus.NOT_FOUND);
        var missing = summary(ben, UUID.randomUUID(), Map.of(), HttpStatus.NOT_FOUND);

        assertThat(hidden.get("code")).isEqualTo("todo.list_not_found");
        assertThat(missing.get("code")).isEqualTo("todo.list_not_found");
    }

    @Test
    void aSharedListIsThere() {
        UUID groceries = list(Map.of("name", "Groceries", "kind", "SHOPPING"));
        todo(groceries, Map.of("title", "Milk", "status", "OPEN"));
        var ben = invite("Ben", "ben");
        share(anna, LIST, groceries, ben, "CHECK");

        var summary = summary(ben, groceries, Map.of(), HttpStatus.OK);

        assertThat((List<Map<String, Object>>) summary.get("items"))
                .extracting(i -> i.get("title"))
                .containsExactly("Milk");
    }

    @Test
    void aDeletedListIsGone() {
        UUID groceries = list(Map.of("name", "Groceries", "kind", "SHOPPING"));
        long version = ((Number) db.fetchValue("select version from todo_list where id = ?", groceries)).longValue();
        phone.push(SyncClient.deletion(LIST, groceries, version));

        summary(anna, groceries, Map.of(), HttpStatus.NOT_FOUND);
    }

    @Test
    void theLimitCutsTheEntriesButNotTheCounts() {
        UUID groceries = list(Map.of("name", "Groceries", "kind", "SHOPPING"));
        for (int i = 1; i <= 3; i++) {
            todo(groceries, Map.of("title", "Item " + i, "status", "OPEN", "position", i * 1000));
        }

        var summary = summary(anna, groceries, Map.of("limit", "2"), HttpStatus.OK);

        assertThat((List<?>) summary.get("items")).hasSize(2);
        assertThat(summary).containsEntry("openCount", 3).containsEntry("truncated", true);
    }

    private Map<String, Object> summary(Family.Session who, UUID listId, Map<String, String> query, HttpStatus status) {
        return rest.get()
                .uri(builder -> {
                    var path = builder.path("/api/v1/todo/lists/" + listId + "/summary");
                    query.forEach(path::queryParam);
                    return path.build();
                })
                .headers(who.auth())
                .exchange()
                .expectStatus()
                .isEqualTo(status)
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
    }

    private UUID list(Map<String, Object> fields) {
        UUID id = UUID.randomUUID();
        var result = phone.push(SyncClient.mutation(LIST, id, null, fields));
        assertThat(result).allMatch(r -> "applied".equals(r.get("status")));
        return id;
    }

    private void todo(UUID listId, Map<String, Object> fields) {
        var withList = new HashMap<>(fields);
        withList.put("listId", listId.toString());
        var result = phone.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, UUID.randomUUID(), null, withList), LIST, listId));
        assertThat(result).allMatch(r -> "applied".equals(r.get("status")));
    }

    private void share(Family.Session owner, String type, UUID id, Family.Session with, String level) {
        rest.put()
                .uri("/api/v1/items/" + type + "/" + id + "/shares")
                .headers(owner.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("shares", List.of(Map.of(
                        "subjectType", "MEMBER", "subjectId", with.memberId().toString(), "level", level))))
                .exchange()
                .expectStatus()
                .isOk();
    }

    private Family.Session invite(String displayName, String username) {
        var invitation = rest.post()
                .uri("/api/v1/invitations")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("validity", "HOURS_24", "groupIds", List.of()))
                .exchange()
                .expectStatus()
                .isCreated()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        return Family.toSession(rest.post()
                .uri("/api/v1/invitations/" + invitation.get("code") + "/redeem")
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "displayName", displayName,
                        "username", username,
                        "password", "bens-langes-passwort",
                        "device", Map.of("deviceName", displayName + "s Phone", "platform", "IOS")))
                .exchange()
                .expectStatus()
                .is2xxSuccessful()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody());
    }
}
