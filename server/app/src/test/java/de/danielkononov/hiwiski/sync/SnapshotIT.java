package de.danielkononov.hiwiski.sync;

import static de.danielkononov.hiwiski.db.generated.Tables.CHANGE_LOG;
import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.jooq.DSLContext;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * A device's first sync: the state, not the history.
 *
 * <p>The log is cleaned up after the retention period. When a fresh
 * device pulled the log from 0, after 90 days it was missing everything nobody had touched
 * since -- and whatever was touched arrived only with the most recently changed fields: a
 * check-off without a title, without a list.
 */
@IntegrationTest
class SnapshotIT {

    private static final String LIST = "TODO_LIST";
    private static final String TODO = "TODO";

    @Autowired RestTestClient rest;

    @Autowired DSLContext db;

    @Test
    void aFreshDeviceGetsEverythingEvenAfterCleanup() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);

        UUID listId = UUID.randomUUID();
        UUID todoId = UUID.randomUUID();
        device.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Einkauf")));
        var created = device.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, todoId, null, Map.of(
                        "title", "Milch", "status", "OPEN", "amount", 2, "unit", "l")),
                LIST,
                listId));
        long version = ((Number) created.get(0).get("version")).longValue();
        device.push(SyncClient.mutation(TODO, todoId, version, Map.of("status", "DONE")));

        // What the cleanup job does after the retention period: the creation is no longer in the log.
        db.deleteFrom(CHANGE_LOG).execute();

        var fresh = new SyncClient(rest, session);
        var changes = fresh.pullSnapshot(500);

        var list = only(changes, listId);
        assertThat(list.get("op")).isEqualTo("upsert");
        assertThat(fields(list)).containsEntry("name", "Einkauf");

        var todo = only(changes, todoId);
        assertThat(todo.get("containerType")).isEqualTo(LIST);
        assertThat(todo.get("containerId")).isEqualTo(listId.toString());
        assertThat(todo.get("entityKey")).isEqualTo("TD-1");
        // All fields, not just the most recently changed one.
        assertThat(fields(todo))
                .containsEntry("title", "Milch")
                .containsEntry("status", "DONE")
                .containsEntry("unit", "l");
        // A number, as it was pushed -- not text the client would choke on.
        assertThat(fields(todo).get("amount")).isInstanceOf(Number.class);
        assertThat(((Number) fields(todo).get("amount")).doubleValue()).isEqualTo(2.0);
    }

    @Test
    void deletedItemsDoNotAppearInTheSnapshot() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);

        UUID kept = UUID.randomUUID();
        UUID gone = UUID.randomUUID();
        device.push(SyncClient.mutation(LIST, kept, null, Map.of("name", "Bleibt")));
        var created = device.push(SyncClient.mutation(LIST, gone, null, Map.of("name", "Geht")));
        device.push(SyncClient.deletion(LIST, gone, ((Number) created.get(0).get("version")).longValue()));

        var changes = new SyncClient(rest, session).pullSnapshot(500);

        assertThat(ids(changes)).contains(kept.toString()).doesNotContain(gone.toString());
    }

    @Test
    void pageByPageEveryItemComesExactlyOnce() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);

        List<String> expected = new java.util.ArrayList<>();
        for (int i = 0; i < 4; i++) {
            UUID listId = UUID.randomUUID();
            UUID todoId = UUID.randomUUID();
            device.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Liste " + i)));
            device.push(SyncClient.withContainer(
                    SyncClient.mutation(TODO, todoId, null, Map.of("title", "Aufgabe " + i)), LIST, listId));
            expected.add(listId.toString());
            expected.add(todoId.toString());
        }

        // Two per page: the boundaries fall in the middle of a type and between two types.
        var changes = new SyncClient(rest, session).pullSnapshot(2);

        var lists = changes.stream().filter(change -> LIST.equals(change.get("entityType"))).toList();
        assertThat(ids(changes)).containsAll(expected).doesNotHaveDuplicates();
        // The list before its tasks: a container never comes after its content.
        int lastList = changes.indexOf(lists.getLast());
        int firstTodo = changes.indexOf(changes.stream()
                .filter(change -> TODO.equals(change.get("entityType")))
                .findFirst()
                .orElseThrow());
        assertThat(lastList).isLessThan(firstTodo);
    }

    @Test
    void afterTheSnapshotTheLogTakesOver() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);
        device.push(SyncClient.mutation(LIST, UUID.randomUUID(), null, Map.of("name", "Vorher")));

        var fresh = new SyncClient(rest, session);
        fresh.pullSnapshot(500);
        assertThat(fresh.lastSeq()).isGreaterThan(0);

        UUID later = UUID.randomUUID();
        device.push(SyncClient.mutation(LIST, later, null, Map.of("name", "Nachher")));

        // Only what happened after the snapshot -- everything before is already in it.
        assertThat(ids(fresh.pullAll())).containsExactly(later.toString());
    }

    private static Map<String, Object> only(List<Map<String, Object>> changes, UUID id) {
        var matching = changes.stream().filter(change -> id.toString().equals(change.get("entityId"))).toList();
        assertThat(matching).hasSize(1);
        return matching.getFirst();
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> fields(Map<String, Object> change) {
        return (Map<String, Object>) change.get("fields");
    }

    private static List<Object> ids(List<Map<String, Object>> changes) {
        return changes.stream().map(change -> change.get("entityId")).toList();
    }
}
