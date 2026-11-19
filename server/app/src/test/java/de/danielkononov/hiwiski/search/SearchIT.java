package de.danielkononov.hiwiski.search;

import static de.danielkononov.hiwiski.db.generated.Tables.TODO;
import static de.danielkononov.hiwiski.db.generated.Tables.TODO_LIST;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.tuple;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.FollowUps;
import de.danielkononov.hiwiski.support.SyncClient;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.jooq.DSLContext;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * The acceptance case for search.
 *
 * <p>"<strong>'kin' finds while typing; 'kinder' finds 'Kinderarzt'</strong>; […]
 * {@code TD-14} jumps. A task's history shows who checked it off and when, and
 * <strong>says how far back it reaches</strong>."
 */
@IntegrationTest
class SearchIT {

    private static final String LIST = "TODO_LIST";
    private static final String TODO_TYPE = "TODO";

    @Autowired RestTestClient rest;
    @Autowired DSLContext db;

    private Family.Session anna;
    private Family.Session ben;
    private SyncClient annasDevice;
    private UUID listId;
    private UUID todoId;

    @BeforeEach
    void aTask() {
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
        var signedIn = rest.post()
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
                .getResponseBody();
        ben = Family.toSession(signedIn);

        annasDevice = new SyncClient(rest, anna);
        listId = UUID.randomUUID();
        todoId = UUID.randomUUID();

        annasDevice.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Haushalt")));
        annasDevice.push(SyncClient.withContainer(
                SyncClient.mutation(TODO_TYPE, todoId, null, Map.of(
                        "title", "Kinderarzt anrufen",
                        "description", "Wegen der Impfung",
                        "status", "OPEN")),
                LIST,
                listId));
        FollowUps.await(db);
    }

    private Map<?, ?> search(String query, Family.Session who) {
        return rest.get()
                .uri("/api/v1/search?q={q}", query)
                .headers(who.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
    }

    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> hits(String query, Family.Session who) {
        return (List<Map<String, Object>>) search(query, who).get("hits");
    }

    @Test
    void kinFindsWhileTyping() {
        // Prefix search: something has to show up after just three letters, otherwise you
        // are typing into the void.
        assertThat(hits("kin", anna))
                .extracting(hit -> hit.get("title"))
                .contains("Kinderarzt anrufen");
    }

    @Test
    void kinderFindsKinderarzt() {
        // **No stemmer splits German compound words**: "kinder" is part of
        // "Kinderarzt" (pediatrician), but `to_tsvector` does not turn it into two words.
        // That is what the word-part match is for.
        assertThat(hits("kinder", anna))
                .extracting(hit -> hit.get("title"))
                .contains("Kinderarzt anrufen");
    }

    @Test
    void theBodyIsSearchedToo() {
        assertThat(hits("Impfung", anna))
                .extracting(hit -> hit.get("title"))
                .contains("Kinderarzt anrufen");
    }

    @Test
    void theHitShowsWhereItWasFound() {
        var hit = hits("Kinderarzt", anna).getFirst();
        // "Haushalt" — where it was found, so you know where the hit comes from.
        assertThat(hit.get("context")).isEqualTo("Haushalt");
        assertThat(hit.get("entityKey")).asString().startsWith("TD-");
    }

    @Test
    void aNumberJumpsStraightThere() {
        String key = db.select(TODO.ENTITY_KEY)
                .from(TODO)
                .where(TODO.ID.eq(todoId))
                .fetchOne(TODO.ENTITY_KEY);

        // **An entered number jumps straight there** instead of running a full-text search.
        var result = search(key, anna);
        @SuppressWarnings("unchecked")
        var jump = (Map<String, Object>) result.get("jumpTo");
        assertThat(jump).isNotNull();
        assertThat(jump.get("itemId")).isEqualTo(todoId.toString());

        // Also with the hash in front, the way it appears in a text.
        @SuppressWarnings("unchecked")
        var withHash = (Map<String, Object>) search("#" + key, anna).get("jumpTo");
        assertThat(withHash).isNotNull();
    }

    @Test
    void whatBenMayNotSeeHeCannotFindEither() {
        // **The share check is part of the same query as the hits.** Two steps would be a
        // time window, and a title already reveals too much.
        assertThat(hits("Kinderarzt", ben)).isEmpty();
        assertThat(search("TD-1", ben).get("jumpTo")).isNull();
    }

    @Test
    void aSpecialCharacterIsNotAServerError() {
        // `to_tsquery` throws a syntax error on `&`. A search field that returns 500 on a
        // special character is broken.
        assertThat(hits("Müll & Co.", anna)).isNotNull();
        assertThat(hits("!!!", anna)).isNotNull();
    }

    @Test
    void whatIsDeletedDisappearsFromTheIndex() {
        long version = db.select(TODO.VERSION).from(TODO).where(TODO.ID.eq(todoId)).fetchOne(TODO.VERSION);
        annasDevice.push(SyncClient.deletion(TODO_TYPE, todoId, version));
        FollowUps.await(db);

        // Otherwise the search would find something that no longer exists — and the jump
        // would lead nowhere.
        assertThat(hits("Kinderarzt", anna)).isEmpty();
    }

    @Test
    void theHistoryShowsWhoCheckedOffWhenAndHowFarBackItReaches() {
        long version = db.select(TODO.VERSION).from(TODO).where(TODO.ID.eq(todoId)).fetchOne(TODO.VERSION);
        annasDevice.push(SyncClient.mutation(TODO_TYPE, todoId, version, Map.of("status", "DONE")));

        var history = rest.get()
                .uri("/api/v1/history/" + TODO_TYPE + "/" + todoId)
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();

        @SuppressWarnings("unchecked")
        var entries = (List<Map<String, Object>>) history.get("entries");
        assertThat(entries).describedAs("create and check off").hasSize(2);

        var newest = entries.getFirst();
        assertThat(newest.get("op")).isEqualTo("upsert");
        assertThat(newest.get("actorId")).isEqualTo(anna.memberId().toString());
        // Which fields were touched -- from `changed_fields`, not diffed after the fact.
        @SuppressWarnings("unchecked")
        var fields = (List<String>) newest.get("fields");
        assertThat(fields).containsExactly("status");
        assertThat(newest.get("status")).isEqualTo("DONE");

        // **The log retention also limits how far back the history reaches — and the UI
        // says so**. Without this information a truncated history looks like
        // a complete one.
        assertThat(history.get("reachesBack")).isNotNull();
    }

    @Test
    void theHistoryTellsCheckingOffFromOpeningAgain() {
        // Both changes touch only `status`; without the value both rows read "Done".
        long version = db.select(TODO.VERSION).from(TODO).where(TODO.ID.eq(todoId)).fetchOne(TODO.VERSION);
        annasDevice.push(SyncClient.mutation(TODO_TYPE, todoId, version, Map.of("status", "DONE")));
        annasDevice.push(SyncClient.mutation(TODO_TYPE, todoId, version + 1, Map.of("status", "OPEN")));

        var history = rest.get()
                .uri("/api/v1/history/" + TODO_TYPE + "/" + todoId)
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();

        @SuppressWarnings("unchecked")
        var entries = (List<Map<String, Object>>) history.get("entries");
        assertThat(entries).extracting(entry -> entry.get("status"))
                .describedAs("opened again, checked off, created open")
                .containsExactly("OPEN", "DONE", "OPEN");
    }

    @Test
    void theHistoryTellsArchivingFromRestoring() {
        // Both changes touch only `archivedAt` and `archivedBy`; without the value both
        // rows read the same.
        long version = db.select(TODO_LIST.VERSION)
                .from(TODO_LIST)
                .where(TODO_LIST.ID.eq(listId))
                .fetchOne(TODO_LIST.VERSION);
        annasDevice.push(SyncClient.mutation(LIST, listId, version, Map.of(
                "archivedAt", java.time.OffsetDateTime.now().toString(),
                "archivedBy", anna.memberId().toString())));
        Map<String, Object> restored = new java.util.HashMap<>();
        restored.put("archivedAt", null);
        restored.put("archivedBy", null);
        annasDevice.push(SyncClient.mutation(LIST, listId, version + 1, restored));

        var history = rest.get()
                .uri("/api/v1/history/" + LIST + "/" + listId)
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();

        @SuppressWarnings("unchecked")
        var entries = (List<Map<String, Object>>) history.get("entries");
        // The list's own changes; the task's creation is in its history too.
        assertThat(entries)
                .filteredOn(entry -> entry.get("entryId") == null)
                .extracting(entry -> entry.get("archived"))
                .describedAs("restored, archived, created (no archive change)")
                .containsExactly(false, true, null);
    }

    @Test
    void aListsHistoryShowsWhatHappenedToItsTasks() {
        // Ticked off or deleted, a task left no trace on its list: one had to open every
        // task to find out.
        long version = db.select(TODO.VERSION).from(TODO).where(TODO.ID.eq(todoId)).fetchOne(TODO.VERSION);
        annasDevice.push(SyncClient.mutation(TODO_TYPE, todoId, version, Map.of("status", "DONE")));
        annasDevice.push(SyncClient.deletion(TODO_TYPE, todoId, version + 1));

        var history = rest.get()
                .uri("/api/v1/history/" + LIST + "/" + listId)
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();

        @SuppressWarnings("unchecked")
        var entries = (List<Map<String, Object>>) history.get("entries");
        assertThat(entries)
                .extracting(entry -> entry.get("op"), entry -> entry.get("status"), entry -> entry.get("entryId"))
                .describedAs("deleted, checked off, created -- the task's; the list's creation last")
                .containsExactly(
                        tuple("delete", null, todoId.toString()),
                        tuple("upsert", "DONE", todoId.toString()),
                        tuple("upsert", "OPEN", todoId.toString()),
                        tuple("upsert", null, null));
        assertThat(entries.getFirst().get("entryTitle")).isEqualTo("Kinderarzt anrufen");
        assertThat(entries.getLast().get("entryTitle")).isNull();
    }

    @Test
    void anAssignmentDoesNotBreakTheHistory() {
        // The assignment shares — and to do so writes `access_granted` to the log, on the
        // same item. Its `op` is not in the contract; the history threw on it and returned
        // 400 instead of the entries.
        long version = db.select(TODO.VERSION).from(TODO).where(TODO.ID.eq(todoId)).fetchOne(TODO.VERSION);
        annasDevice.push(SyncClient.mutation(
                TODO_TYPE, todoId, version, Map.of("assignees", List.of(ben.memberId().toString()))));

        var history = rest.get()
                .uri("/api/v1/history/" + TODO_TYPE + "/" + todoId)
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();

        @SuppressWarnings("unchecked")
        var entries = (List<Map<String, Object>>) history.get("entries");
        assertThat(entries).extracting(entry -> entry.get("op")).containsOnly("upsert");
    }

    @Test
    void whatBenMayNotSeeHasNoHistoryForHimEither() {
        rest.get()
                .uri("/api/v1/history/" + TODO_TYPE + "/" + todoId)
                .headers(ben.auth())
                .exchange()
                // 404 and not 403: whoever may not see the item must not be able to tell
                // from the response that it exists.
                .expectStatus()
                .isNotFound();
    }

    /**
     * A task assigned to Ben in Anna's private list is his to find -- the list's name is
     * not. "Even a title gives away too much."
     */
    @Test
    void theContextShowsOnlyWhatTheReaderMaySee() {
        UUID presents = UUID.randomUUID();
        UUID task = UUID.randomUUID();
        annasDevice.push(SyncClient.mutation(LIST, presents, null, Map.of("name", "Geschenke für Ben")));
        annasDevice.push(SyncClient.withContainer(
                SyncClient.mutation(TODO_TYPE, task, null, Map.of(
                        "title", "Fahrradhelm abholen",
                        "status", "OPEN",
                        "assignees", List.of(ben.memberId().toString()))),
                LIST,
                presents));

        UUID privat = UUID.randomUUID();
        UUID shared = UUID.randomUUID();
        annasDevice.push(SyncClient.mutation(
                "WIKI_PAGE", privat, null, Map.of("title", "Privat", "kind", "PAGE", "content", "")));
        annasDevice.push(SyncClient.withContainer(
                SyncClient.mutation(
                        "WIKI_PAGE", shared, null, Map.of("title", "Fahrradtour", "kind", "PAGE", "content", "")),
                "WIKI_PAGE",
                privat));
        rest.put()
                .uri("/api/v1/items/WIKI_PAGE/" + shared + "/shares")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("shares", List.of(Map.of(
                        "subjectType", "MEMBER", "subjectId", ben.memberId().toString(), "level", "READ"))))
                .exchange()
                .expectStatus()
                .isOk();
        FollowUps.await(db);

        assertThat(hits("Fahrrad", ben))
                .extracting(hit -> hit.get("title"), hit -> hit.get("context"))
                .containsExactlyInAnyOrder(
                        org.assertj.core.groups.Tuple.tuple("Fahrradhelm abholen", null),
                        org.assertj.core.groups.Tuple.tuple("Fahrradtour", null));
        assertThat(hits("Fahrrad", anna))
                .extracting(hit -> hit.get("context"))
                .containsExactlyInAnyOrder("Geschenke für Ben", "Privat");
    }

    /** A page deep in the tree names its whole path, from the top down. */
    @Test
    void theContextOfAPageIsItsPathFromTheTop() {
        UUID house = UUID.randomUUID();
        UUID heating = UUID.randomUUID();
        UUID manual = UUID.randomUUID();
        annasDevice.push(SyncClient.mutation(
                "WIKI_PAGE", house, null, Map.of("title", "Haus", "kind", "PAGE", "content", "")));
        annasDevice.push(SyncClient.withContainer(
                SyncClient.mutation(
                        "WIKI_PAGE", heating, null, Map.of("title", "Heizung", "kind", "PAGE", "content", "")),
                "WIKI_PAGE",
                house));
        annasDevice.push(SyncClient.withContainer(
                SyncClient.mutation(
                        "WIKI_PAGE", manual, null, Map.of("title", "Wartungsanleitung", "kind", "PAGE", "content", "")),
                "WIKI_PAGE",
                heating));
        FollowUps.await(db);

        assertThat(hits("Wartungsanleitung", anna))
                .extracting(hit -> hit.get("context"))
                .containsExactly("Haus › Heizung");
    }

    /** "%" and "_" are what the user typed, not wildcards. */
    @Test
    void wildcardsAreText() {
        annasDevice.push(SyncClient.withContainer(
                SyncClient.mutation(TODO_TYPE, UUID.randomUUID(), null, Map.of("title", "Rabatt 100% nutzen")),
                LIST,
                listId));
        FollowUps.await(db);

        assertThat(hits("%", anna)).extracting(hit -> hit.get("title")).containsExactly("Rabatt 100% nutzen");
        assertThat(hits("Kinder_rzt", anna)).isEmpty();
    }
}
