package de.danielkononov.hiwiski.sync;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.FollowUps;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.jooq.DSLContext;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * The archive: kept, read-only, restorable — and out of the way in search.
 *
 * <p>Read-only is the server's rule, not only the app's: a device that was offline when
 * someone archived the list must not keep writing into it.
 */
@IntegrationTest
class ArchiveIT {

    private static final String LIST = "TODO_LIST";
    private static final String TODO = "TODO";
    private static final String PAGE = "WIKI_PAGE";

    @Autowired RestTestClient rest;
    @Autowired DSLContext db;

    private Family.Session anna;
    private SyncClient device;

    @BeforeEach
    void signIn() {
        anna = Family.setUp(rest);
        device = new SyncClient(rest, anna);
    }

    private static Map<String, Object> archived(UUID by) {
        return Map.of("archivedAt", OffsetDateTime.now().toString(), "archivedBy", by.toString());
    }

    private static Map<String, Object> restored() {
        Map<String, Object> fields = new HashMap<>();
        fields.put("archivedAt", null);
        fields.put("archivedBy", null);
        return fields;
    }

    private static long version(List<Map<String, Object>> results) {
        return ((Number) results.getFirst().get("version")).longValue();
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> pushOne(Map<String, Object> mutation) {
        return device.push(mutation).getFirst();
    }

    @Test
    void anArchivedListIsReadOnlyUntilRestored() {
        UUID listId = UUID.randomUUID();
        UUID todoId = UUID.randomUUID();
        long listVersion = version(device.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Umzug 2025"))));
        long todoVersion = version(device.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, todoId, null, Map.of("title", "Kartons", "status", "OPEN")), LIST, listId)));

        var archive = pushOne(SyncClient.mutation(LIST, listId, listVersion, archived(anna.memberId())));
        assertThat(archive.get("status")).isEqualTo("applied");
        long archivedVersion = ((Number) archive.get("version")).longValue();

        // The list itself, a task in it, a new task, a checked-off task: all refused.
        var rename = pushOne(SyncClient.mutation(LIST, listId, archivedVersion, Map.of("name", "Umzug")));
        var check = pushOne(SyncClient.withContainer(
                SyncClient.mutation(TODO, todoId, todoVersion, Map.of("status", "DONE")), LIST, listId));
        var add = pushOne(SyncClient.withContainer(
                SyncClient.mutation(TODO, UUID.randomUUID(), null, Map.of("title", "Noch was")), LIST, listId));
        assertThat(List.of(rename, check, add))
                .allSatisfy(result -> {
                    assertThat(result.get("status")).isEqualTo("rejected");
                    assertThat(result.get("code")).isEqualTo("archive.read_only");
                });

        // Restoring is the one change it takes — and then it is editable again.
        var restore = pushOne(SyncClient.mutation(LIST, listId, archivedVersion, restored()));
        assertThat(restore.get("status")).isEqualTo("applied");
        var renameAfter = pushOne(SyncClient.mutation(
                LIST, listId, ((Number) restore.get("version")).longValue(), Map.of("name", "Umzug")));
        assertThat(renameAfter.get("status")).isEqualTo("applied");
    }

    @Test
    void anArchivedListCanStillBeDeleted() {
        UUID listId = UUID.randomUUID();
        long version = version(device.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Alt"))));
        long archivedVersion = version(device.push(SyncClient.mutation(LIST, listId, version, archived(anna.memberId()))));

        var deletion = pushOne(SyncClient.deletion(LIST, listId, archivedVersion));

        // The archive is no protection against deleting: it goes to the trash from here.
        assertThat(deletion.get("status")).isEqualTo("applied");
    }

    @Test
    void onlyThisPageLeavesItsSubpagesEditable() {
        UUID parentId = UUID.randomUUID();
        UUID childId = UUID.randomUUID();
        long parentVersion = version(device.push(SyncClient.mutation(PAGE, parentId, null, Map.of("title", "Alte Wohnung", "kind", "PAGE"))));
        long childVersion = version(device.push(SyncClient.withContainer(
                SyncClient.mutation(PAGE, childId, null, Map.of("title", "Nebenkosten", "kind", "PAGE", "parentId", parentId.toString())),
                PAGE,
                parentId)));

        long archivedVersion =
                version(device.push(SyncClient.mutation(PAGE, parentId, parentVersion, archived(anna.memberId()))));

        // The subpage stays active: "only this page" (archive).
        var editChild = pushOne(SyncClient.withContainer(
                SyncClient.mutation(PAGE, childId, childVersion, Map.of("title", "Nebenkosten 2025")), PAGE, parentId));
        assertThat(editChild.get("status")).isEqualTo("applied");

        // The archived page is read-only, and nothing new goes under it.
        var editParent = pushOne(SyncClient.mutation(PAGE, parentId, archivedVersion, Map.of("content", "Neu")));
        var newChild = pushOne(SyncClient.withContainer(
                SyncClient.mutation(PAGE, UUID.randomUUID(), null, Map.of("title", "Neu", "kind", "PAGE", "parentId", parentId.toString())),
                PAGE,
                parentId));
        assertThat(List.of(editParent, newChild))
                .allSatisfy(result -> assertThat(result.get("code")).isEqualTo("archive.read_only"));

        // Moving a page there is placing it there.
        UUID otherId = UUID.randomUUID();
        long otherVersion = version(device.push(SyncClient.mutation(PAGE, otherId, null, Map.of("title", "Einkauf", "kind", "PAGE"))));
        var move = pushOne(SyncClient.withContainer(
                SyncClient.mutation(PAGE, otherId, otherVersion, Map.of("parentId", parentId.toString())), PAGE, parentId));
        assertThat(move.get("code")).isEqualTo("archive.read_only");
    }

    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> hits(String query, boolean includeArchived) {
        var body = rest.get()
                .uri("/api/v1/search?q={q}&includeArchived={archived}", query, includeArchived)
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        return (List<Map<String, Object>>) body.get("hits");
    }

    @Test
    void searchLeavesTheArchiveOutUnlessAsked() {
        UUID listId = UUID.randomUUID();
        UUID todoId = UUID.randomUUID();
        long listVersion = version(device.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Umzug 2025"))));
        device.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, todoId, null, Map.of("title", "Umzugskartons besorgen", "status", "OPEN")),
                LIST,
                listId));
        FollowUps.await(db);
        assertThat(hits("Umzugskartons", false)).hasSize(1);

        // Archiving the list archives its tasks in the index too, without touching them.
        device.push(SyncClient.mutation(LIST, listId, listVersion, archived(anna.memberId())));
        FollowUps.await(db);

        assertThat(hits("Umzugskartons", false)).isEmpty();
        assertThat(hits("Umzugskartons", true))
                .singleElement()
                .satisfies(hit -> assertThat(hit.get("archived")).isEqualTo(true));
    }

    @Test
    void anArchivedListIsFoundByItsNameThroughTheArchive() {
        UUID listId = UUID.randomUUID();
        long listVersion = version(device.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Sommerhaus"))));
        FollowUps.await(db);
        assertThat(hits("Sommerhaus", false))
                .singleElement()
                .satisfies(hit -> assertThat(hit.get("itemType")).isEqualTo("TODO_LIST"));

        device.push(SyncClient.mutation(LIST, listId, listVersion, archived(anna.memberId())));
        FollowUps.await(db);

        assertThat(hits("Sommerhaus", false)).isEmpty();
        assertThat(hits("Sommerhaus", true))
                .singleElement()
                .satisfies(hit -> {
                    assertThat(hit.get("itemId")).isEqualTo(listId.toString());
                    assertThat(hit.get("archived")).isEqualTo(true);
                });
    }
}
