package de.danielkononov.hiwiski.sync;

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
 * The sync acceptance case -- <strong>the case everything hinges on</strong>.
 *
 * <p>"App offline, send three mutations, meanwhile change the same objects from a second
 * device, then reconnect. Nothing is lost, the conflict is visible, the chain does not
 * break."
 */
@IntegrationTest
class SyncIT {

    private static final String LIST = "TODO_LIST";
    private static final String TODO = "TODO";
    private static final String OCCURRENCE = "TODO_OCCURRENCE";

    @Autowired RestTestClient rest;

    private SyncClient phone;
    private SyncClient laptop;

    private void twoDevices() {
        var first = Family.setUp(rest);
        var second = Family.login(rest, "anna", "geheim-genug", "Laptop");
        phone = new SyncClient(rest, first);
        laptop = new SyncClient(rest, second);
    }

    private static long version(Map<String, Object> result) {
        return ((Number) result.get("version")).longValue();
    }

    private static Map<String, Object> change(List<Map<String, Object>> changes, UUID entityId) {
        return changes.stream()
                .filter(change -> entityId.toString().equals(change.get("entityId")))
                .reduce((first, second) -> second)
                .orElseThrow(() -> new AssertionError("no entry for " + entityId));
    }

    /**
     * Layers the fields on top of each other -- just as the client does.
     *
     * <p>Every log entry carries only the fields changed by <em>this</em> mutation. Never
     * whole objects: otherwise an older app would blank out fields it does not know.
     */
    @SuppressWarnings("unchecked")
    private static Map<String, Object> merged(List<Map<String, Object>> changes, UUID entityId) {
        Map<String, Object> state = new java.util.LinkedHashMap<>();
        changes.stream()
                .filter(change -> entityId.toString().equals(change.get("entityId")))
                .forEach(change -> state.putAll((Map<String, Object>) change.get("fields")));
        return state;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> fields(Map<String, Object> change) {
        return (Map<String, Object>) change.get("fields");
    }

    @Test
    void whatOneDeviceCreatesArrivesOnTheOther() {
        twoDevices();
        UUID listId = UUID.randomUUID();
        UUID todoId = UUID.randomUUID();

        var results = phone.push(
                SyncClient.mutation(LIST, listId, null, Map.of("name", "Haushalt", "kind", "STANDARD")),
                SyncClient.withContainer(
                        SyncClient.mutation(TODO, todoId, null, Map.of("title", "Müll rausbringen")),
                        LIST,
                        listId));

        assertThat(results).extracting(result -> result.get("status")).containsExactly("applied", "applied");

        var changes = laptop.pullAll();
        assertThat(fields(change(changes, listId)).get("name")).isEqualTo("Haushalt");
        assertThat(fields(change(changes, todoId)).get("title")).isEqualTo("Müll rausbringen");
        // The container is in the envelope, not in the fields -- the share depends on
        // it.
        assertThat(change(changes, todoId).get("containerType")).isEqualTo(LIST);
        assertThat(change(changes, todoId).get("containerId")).isEqualTo(listId.toString());
    }

    @Test
    void theReadableKeyIsAssignedExactlyOnce() {
        twoDevices();
        UUID listId = UUID.randomUUID();
        UUID todoId = UUID.randomUUID();
        phone.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Haushalt")));

        var first = phone.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, todoId, null, Map.of("title", "Müll")), LIST, listId));
        assertThat(first.get(0).get("entityKey")).isEqualTo("TD-1");

        var second = phone.push(SyncClient.mutation(TODO, todoId, version(first.get(0)), Map.of("title", "Biomüll")));
        // It never changes once assigned -- a number someone wrote down stays valid.
        assertThat(second.get(0).get("entityKey")).isEqualTo("TD-1");
    }

    /**
     * The acceptance case.
     *
     * <p>Three mutations offline, while the second device changes the same object.
     */
    @Test
    void offlineThreeMutationsChangedInParallelNothingIsLost() {
        twoDevices();
        UUID listId = UUID.randomUUID();
        UUID todoId = UUID.randomUUID();

        // Starting point, known to both.
        phone.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Haushalt")));
        var created = phone.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, todoId, null, Map.of("title", "Müll rausbringen", "status", "OPEN")),
                LIST,
                listId));
        long knownVersion = version(created.get(0));
        laptop.pullAll();

        // The phone goes offline. Meanwhile the laptop moves the due date.
        var laptopChange =
                laptop.push(SyncClient.mutation(TODO, todoId, knownVersion, Map.of("dueDate", "2026-10-02")));
        assertThat(laptopChange.get(0).get("status")).isEqualTo("applied");

        // The phone comes back -- with three mutations based on the old state.
        var results = phone.push(
                // 1. A different field: goes through even though the state is old.
                //    Whoever checks off while someone else moves the due date loses
                //    nothing.
                SyncClient.mutation(TODO, todoId, knownVersion, Map.of("status", "DONE")),
                // 2. The same field as the laptop: conflict, visible.
                SyncClient.mutation(TODO, todoId, knownVersion, Map.of("dueDate", "2026-10-09")),
                // 3. A new task in the same list: the chain does not break.
                SyncClient.withContainer(
                        SyncClient.mutation(TODO, UUID.randomUUID(), null, Map.of("title", "Fenster putzen")),
                        LIST,
                        listId));

        assertThat(results.get(0).get("status")).isEqualTo("applied");

        assertThat(results.get(1).get("status")).isEqualTo("conflict");
        assertThat(List.copyOf((List<?>) results.get(1).get("conflictFields"))).isEqualTo(List.of("dueDate"));
        // The server value is included -- without it the UI could not write the
        // banner.
        assertThat(((Map<?, ?>) results.get(1).get("serverFields")).get("dueDate")).isEqualTo("2026-10-02");

        assertThat(results.get(2).get("status")).isEqualTo("applied");

        // Nothing is lost: the check-off is there, the laptop's due date stands.
        laptop.setLastSeq(0);
        var changes = laptop.pullAll();
        var todo = merged(changes, todoId);
        assertThat(todo).containsEntry("status", "DONE");
        assertThat(todo).containsEntry("dueDate", "2026-10-02");
    }

    /**
     * A device that saves twice before the first answer arrives -- or edits twice
     * offline -- sends the old version both times. Its own first write is what the second
     * one built on, not a conflict. Before, the second save collided with the first, and
     * the device even got its own older text back.
     */
    @Test
    void aDeviceDoesNotCollideWithItsOwnEarlierWrite() {
        twoDevices();
        UUID listId = UUID.randomUUID();
        UUID todoId = UUID.randomUUID();
        phone.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Household")));
        long base = version(phone.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, todoId, null, Map.of("title", "Bins")), LIST, listId)).get(0));

        var results = phone.push(
                SyncClient.mutation(TODO, todoId, base, Map.of("title", "Bins out")),
                SyncClient.mutation(TODO, todoId, base, Map.of("title", "Bins out tonight")));

        assertThat(results).allMatch(result -> "applied".equals(result.get("status")));
        laptop.setLastSeq(0);
        assertThat(merged(laptop.pullAll(), todoId)).containsEntry("title", "Bins out tonight");
    }

    @Test
    void aRetriedMutationDoesNotCreateADuplicate() {
        twoDevices();
        UUID listId = UUID.randomUUID();
        var mutation = SyncClient.mutation(LIST, listId, null, Map.of("name", "Haushalt"));

        var first = phone.push(mutation);
        var again = phone.push(mutation);

        assertThat(first.get(0).get("status")).isEqualTo("applied");
        // A retry after a dropped connection counts as success, not as a second record.
        assertThat(again.get(0).get("status")).isEqualTo("duplicate");

        var changes = laptop.pullAll();
        assertThat(changes.stream().filter(change -> listId.toString().equals(change.get("entityId"))))
                .hasSize(1);
    }

    @Test
    void completedOccurrencesAreAddedNotReplaced() {
        twoDevices();
        UUID listId = UUID.randomUUID();
        UUID todoId = UUID.randomUUID();
        phone.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Haushalt")));
        phone.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, todoId, null, Map.of("title", "Müll", "rrule", "FREQ=WEEKLY")),
                LIST,
                listId));

        // Two devices check off different occurrences while offline.
        UUID mondayId = UUID.randomUUID();
        UUID tuesdayId = UUID.randomUUID();
        phone.push(SyncClient.withContainer(
                SyncClient.mutation(
                        OCCURRENCE, mondayId, null, Map.of("occurrenceDate", "2026-10-05", "doneAt", "2026-10-05T08:00:00Z")),
                TODO,
                todoId));
        laptop.push(SyncClient.withContainer(
                SyncClient.mutation(
                        OCCURRENCE, tuesdayId, null, Map.of("occurrenceDate", "2026-10-12", "doneAt", "2026-10-12T08:00:00Z")),
                TODO,
                todoId));

        // Both go through. As a field on the task the list would count as a whole, and
        // the second device would overwrite the first one's check -- exactly what an earlier version
        // forgot with event.exceptions.
        laptop.setLastSeq(0);
        var changes = laptop.pullAll();
        assertThat(fields(change(changes, mondayId)).get("occurrenceDate")).isEqualTo("2026-10-05");
        assertThat(fields(change(changes, tuesdayId)).get("occurrenceDate")).isEqualTo("2026-10-12");
    }

    @Test
    void aDeletionArrivesAsATombstone() {
        twoDevices();
        UUID listId = UUID.randomUUID();
        var created = phone.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Haushalt")));
        laptop.pullAll();

        phone.push(SyncClient.deletion(LIST, listId, version(created.get(0))));

        // Without a tombstone a client that was offline never learns of it and recreates
        // the item on its next push.
        var changes = laptop.pullAll();
        assertThat(change(changes, listId).get("op")).isEqualTo("delete");
    }

    @Test
    void anUnknownTypeIsRejectedAndDoesNotCrash() {
        twoDevices();
        // A newer client against an older server. That is the price of property 2, and it
        // must not be a server error.
        var results = phone.push(SyncClient.mutation("DOES_NOT_EXIST", UUID.randomUUID(), null, Map.of("a", "b")));

        assertThat(results.get(0).get("status")).isEqualTo("rejected");
        assertThat(results.get(0).get("code")).isEqualTo("sync.unknown_entity_type");
    }

    /**
     * A value of the wrong type rejects its own mutation and nothing else. It used to fail
     * the whole push with a 500, the device sent the batch again, failed at the same place
     * -- and its outbox never drained.
     */
    @Test
    void aMalformedFieldRejectsOnlyItsMutation() {
        twoDevices();
        UUID listId = UUID.randomUUID();
        var results = phone.push(
                SyncClient.mutation(LIST, listId, null, Map.of("name", "Haushalt")),
                SyncClient.withContainer(
                        SyncClient.mutation(TODO, UUID.randomUUID(), null, Map.of("title", "A", "position", "3")),
                        LIST,
                        listId),
                SyncClient.withContainer(
                        SyncClient.mutation(TODO, UUID.randomUUID(), null, Map.of("title", "B", "dueDate", "morgen")),
                        LIST,
                        listId),
                SyncClient.withContainer(
                        SyncClient.mutation(TODO, UUID.randomUUID(), null, Map.of("title", "C", "productId", "kein")),
                        LIST,
                        listId),
                SyncClient.withContainer(
                        SyncClient.mutation(TODO, UUID.randomUUID(), null, Map.of("title", "D")), LIST, listId));

        assertThat(results.stream().map(result -> result.get("status")))
                .containsExactly("applied", "rejected", "rejected", "rejected", "applied");
        assertThat(results.subList(1, 4)).allMatch(result -> "sync.invalid_field".equals(result.get("code")));
    }

    /**
     * A change to fields this server does not know -- from a newer client -- or to none
     * at all changes nothing, and is no conflict: there is nothing in it to show.
     */
    @Test
    void aMutationWithoutKnownFieldsChangesNothing() {
        twoDevices();
        UUID listId = UUID.randomUUID();
        long version = version(phone.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Haushalt")))
                .getFirst());

        for (Map<String, Object> fields : List.<Map<String, Object>>of(Map.of(), Map.of("fromTheFuture", "x"))) {
            var result = phone.push(SyncClient.mutation(LIST, listId, version, fields)).getFirst();

            assertThat(result.get("status")).isEqualTo("applied");
            assertThat(version(result)).isEqualTo(version);
        }
    }

    /**
     * Two devices delete the same list offline. The second delete has arrived already --
     * it must not delete again, log again, or restart the trash's clock.
     */
    @Test
    void aSecondDeleteOfTheSameItemChangesNothing() {
        twoDevices();
        UUID listId = UUID.randomUUID();
        long version = version(phone.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Haushalt")))
                .getFirst());

        var first = phone.push(SyncClient.deletion(LIST, listId, version)).getFirst();
        phone.pullAll();
        var deletions = laptop.pullAll().stream()
                .filter(change -> listId.toString().equals(change.get("entityId")) && "delete".equals(change.get("op")))
                .count();
        var second = laptop.push(SyncClient.deletion(LIST, listId, version)).getFirst();

        assertThat(second.get("status")).isEqualTo("applied");
        assertThat(version(second)).isEqualTo(version(first));
        assertThat(deletions).isEqualTo(1);
        assertThat(phone.pullAll())
                .noneMatch(change -> listId.toString().equals(change.get("entityId")) && "delete".equals(change.get("op")));
    }

    /** "Write down what disappears with it" -- for a list, its tasks and their occurrences. */
    @Test
    void aDeletedListTakesItsTasksAlong() {
        twoDevices();
        UUID listId = UUID.randomUUID();
        UUID first = UUID.randomUUID();
        UUID second = UUID.randomUUID();
        UUID done = UUID.randomUUID();
        long version = version(phone.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Haushalt")))
                .getFirst());
        phone.push(
                SyncClient.withContainer(SyncClient.mutation(TODO, first, null, Map.of("title", "A")), LIST, listId),
                SyncClient.withContainer(SyncClient.mutation(TODO, second, null, Map.of("title", "B")), LIST, listId));
        phone.push(SyncClient.withContainer(
                SyncClient.mutation(OCCURRENCE, done, null, Map.of("occurrenceDate", "2026-10-08")), TODO, first));
        laptop.pullAll();

        phone.push(SyncClient.deletion(LIST, listId, version));

        assertThat(laptop.pullAll().stream()
                        .filter(change -> "delete".equals(change.get("op")))
                        .map(change -> change.get("entityId")))
                .containsExactlyInAnyOrder(listId.toString(), first.toString(), second.toString(), done.toString());
    }

    @Test
    void otherMembersItemsDoNotShowUpInTheLog() {
        var anna = Family.setUp(rest);
        var annasPhone = new SyncClient(rest, anna);

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
                        "device", Map.of("deviceName", "Bens Tablet", "platform", "ANDROID")))
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        var ben = new SyncClient(rest, Family.toSession(bensSignIn));

        UUID listId = UUID.randomUUID();
        annasPhone.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Annas Liste")));

        // The log is delivered filtered per user. Otherwise it leaks the existence and
        // metadata of items the user may not see.
        assertThat(ben.pullAll()).isEmpty();
    }
}
