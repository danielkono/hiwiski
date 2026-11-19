package de.danielkononov.hiwiski.access;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
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
 * The acceptance case for ownership and sharing.
 *
 * <p>"Share a list while the recipient's device is offline → after reconnecting it is
 * there, including its history. Revoke the share → it disappears locally. Grant the
 * <em>check off</em> level → the checkbox works, the title does not."
 */
@IntegrationTest
class AccessIT {

    private static final String LIST = "TODO_LIST";
    private static final String TODO = "TODO";

    @Autowired RestTestClient rest;
    @Autowired DSLContext db;

    private Family.Session anna;
    private Family.Session ben;
    private SyncClient annasDevice;
    private SyncClient bensDevice;
    private UUID listId;
    private UUID todoId;

    @BeforeEach
    void familyWithTwoMembers() {
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
        bensDevice = new SyncClient(rest, ben);

        listId = UUID.randomUUID();
        todoId = UUID.randomUUID();
        annasDevice.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Haushalt")));
        annasDevice.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, todoId, null, Map.of("title", "Müll rausbringen", "status", "OPEN")),
                LIST,
                listId));
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
    void withoutAShareThereIsNothingToSee() {
        // The log is delivered filtered per user. Otherwise it leaks the existence and
        // metadata of items the user may not see.
        assertThat(bensDevice.pullAll()).isEmpty();

        // The sheet says nothing either -- 404 and not 403: a 403 would reveal existence.
        rest.get()
                .uri("/api/v1/items/" + LIST + "/" + listId + "/shares")
                .headers(ben.auth())
                .exchange()
                .expectStatus()
                .isNotFound();
    }

    @Test
    void theSnapshotShowsOnlyWhatIsShared() {
        // The same filter as on the log: the state does not reveal anything that is not
        // shared either.
        assertThat(bensDevice.pullSnapshot(500)).isEmpty();

        share("WRITE");

        assertThat(bensDevice.pullSnapshot(500).stream().map(change -> change.get("entityId")))
                .containsExactlyInAnyOrder(listId.toString(), todoId.toString());
    }

    @Test
    void aShareTakesEffectRetroactivelyEvenIfTheDeviceWasOffline() {
        // Ben's device was offline and never saw the beginning.
        bensDevice.pullAll();
        long bensPosition = bensDevice.lastSeq();

        share("WRITE");

        // Sync runs on a sequence number: the history lies BEFORE Ben's position, he would
        // never get it. Hence the synthetic entry.
        var afterTheShare = bensDevice.pullAll();
        assertThat(afterTheShare)
                .anyMatch(change -> "access_granted".equals(change.get("op"))
                        && listId.toString().equals(change.get("entityId")));
        assertThat(bensDevice.lastSeq()).isGreaterThan(bensPosition);

        // In response the client pulls the container again in full -- and then the history
        // is there.
        bensDevice.setLastSeq(0);
        var fromScratch = bensDevice.pullAll();
        assertThat(fromScratch)
                .anyMatch(change -> listId.toString().equals(change.get("entityId"))
                        && "upsert".equals(change.get("op")));
        assertThat(fromScratch)
                .anyMatch(change -> todoId.toString().equals(change.get("entityId"))
                        && "upsert".equals(change.get("op")));
    }

    private UUID createGroup(String name, List<UUID> memberIds) {
        var group = rest.post()
                .uri("/api/v1/groups")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("name", name, "memberIds", memberIds.stream().map(UUID::toString).toList()))
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        return UUID.fromString((String) group.get("id"));
    }

    private void setGroupMembers(UUID groupId, String name, List<UUID> memberIds) {
        rest.patch()
                .uri("/api/v1/groups/" + groupId)
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("name", name, "memberIds", memberIds.stream().map(UUID::toString).toList()))
                .exchange()
                .expectStatus()
                .isOk();
    }

    private void shareWithGroup(UUID groupId) {
        rest.put()
                .uri("/api/v1/items/" + LIST + "/" + listId + "/shares")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("shares", List.of(Map.of(
                        "subjectType", "GROUP", "subjectId", groupId.toString(), "level", "READ"))))
                .exchange()
                .expectStatus()
                .isOk();
    }

    /**
     * A group is resolved when access is computed. Someone who joins it afterwards must
     * still get what was shared with it — including the history before their position.
     */
    @Test
    void joiningAGroupLaterGrantsWhatWasSharedWithIt() {
        UUID parents = createGroup("Parents", List.of(anna.memberId()));
        shareWithGroup(parents);
        assertThat(bensDevice.pullAll()).isEmpty();
        long bensPosition = bensDevice.lastSeq();

        setGroupMembers(parents, "Parents", List.of(anna.memberId(), ben.memberId()));

        assertThat(bensDevice.pullAll())
                .anyMatch(change -> "access_granted".equals(change.get("op"))
                        && listId.toString().equals(change.get("entityId")));
        assertThat(bensDevice.lastSeq()).isGreaterThan(bensPosition);
        assertThat(bensDevice.pullSnapshot(500).stream().map(change -> change.get("entityId")))
                .containsExactlyInAnyOrder(listId.toString(), todoId.toString());
    }

    @Test
    void leavingAGroupRevokesWhatWasSharedWithIt() {
        UUID parents = createGroup("Parents", List.of(anna.memberId(), ben.memberId()));
        shareWithGroup(parents);
        bensDevice.pullAll();

        setGroupMembers(parents, "Parents", List.of(anna.memberId()));

        assertThat(bensDevice.pullAll())
                .anyMatch(change -> "access_revoked".equals(change.get("op"))
                        && listId.toString().equals(change.get("entityId")));
        assertThat(bensDevice.pullSnapshot(500)).isEmpty();
    }

    /** The same for an assignment: assigning a task to a group reaches its new members. */
    @Test
    void anAssignmentToAGroupReachesWhoJoinsLater() {
        UUID parents = createGroup("Parents", List.of(anna.memberId()));
        annasDevice.push(SyncClient.mutation(
                TODO, todoId, null, Map.of("assignees", List.of(parents.toString()))));
        assertThat(bensDevice.pullSnapshot(500)).isEmpty();

        setGroupMembers(parents, "Parents", List.of(anna.memberId(), ben.memberId()));

        assertThat(bensDevice.pullSnapshot(500).stream().map(change -> change.get("entityId")))
                .contains(todoId.toString());
    }

    /** A deleted group's shares go with it, and what they granted is taken back. */
    @Test
    void deletingAGroupRemovesItsShares() {
        UUID parents = createGroup("Parents", List.of(anna.memberId(), ben.memberId()));
        shareWithGroup(parents);
        bensDevice.pullAll();

        rest.delete()
                .uri("/api/v1/groups/" + parents)
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .is2xxSuccessful();

        assertThat(bensDevice.pullSnapshot(500)).isEmpty();
        rest.get()
                .uri("/api/v1/items/" + LIST + "/" + listId + "/shares")
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.entries[?(@.subjectType=='GROUP')]")
                .isEmpty();
    }

    /** A group nobody is in yet is still a group: assigning to it is fine and reaches nobody. */
    @Test
    void anAssignmentToAnEmptyGroupIsNoMember() {
        UUID kids = createGroup("Kids", List.of());

        var result = annasDevice.push(SyncClient.mutation(
                TODO, todoId, null, Map.of("assignees", List.of(kids.toString()))));

        assertThat(result.getFirst().get("status")).isEqualTo("applied");
        setGroupMembers(kids, "Kids", List.of(ben.memberId()));
        assertThat(bensDevice.pullSnapshot(500).stream().map(change -> change.get("entityId")))
                .contains(todoId.toString());
    }

    /** *Check off* only exists where something can be ticked -- not on a calendar. */
    @Test
    void checkOffIsRefusedWhereNothingCanBeTicked() {
        UUID calendarId = UUID.randomUUID();
        annasDevice.push(SyncClient.mutation("CALENDAR", calendarId, null, Map.of("name", "Family")));

        rest.put()
                .uri("/api/v1/items/CALENDAR/" + calendarId + "/shares")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("shares", List.of(Map.of(
                        "subjectType", "MEMBER", "subjectId", ben.memberId().toString(), "level", "CHECK"))))
                .exchange()
                .expectStatus()
                .is4xxClientError()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("access.check_not_applicable");
    }

    /** *Check off* ticks boxes -- "no deleting" is part of the level. */
    @Test
    void checkOffDoesNotDelete() {
        share("CHECK");
        var list = bensDevice.pullSnapshot(500).stream()
                .filter(change -> listId.toString().equals(change.get("entityId")))
                .findFirst()
                .orElseThrow();
        long version = ((Number) list.get("version")).longValue();

        var result = bensDevice.push(SyncClient.deletion(LIST, listId, version));

        assertThat(result.getFirst().get("status")).isEqualTo("rejected");
        assertThat(result.getFirst().get("code")).isEqualTo("access.denied");
    }

    @Test
    void aRevocationArrivesAsItsOwnEntry() {
        share("WRITE");
        bensDevice.pullAll();

        // Take it back: empty list. An own share replaces the inherited one, it does not
        // add to it -- and none means none.
        rest.put()
                .uri("/api/v1/items/" + LIST + "/" + listId + "/shares")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("shares", List.of()))
                .exchange()
                .expectStatus()
                .isOk();

        var afterTheRevocation = bensDevice.pullAll();
        // The revocation has to arrive even though access is already gone -- otherwise the
        // device would never learn of it and would keep the data.
        assertThat(afterTheRevocation)
                .anyMatch(change -> "access_revoked".equals(change.get("op"))
                        && listId.toString().equals(change.get("entityId")));
    }

    /** Where nothing changed, nothing is written: a server start recomputes everything. */
    @Test
    void recomputingAnUnchangedShareLeavesItsRowsAlone() {
        share("WRITE");
        String rows = "select string_agg(ctid::text, ',' order by member_id) from effective_access"
                + " where item_id in ('" + listId + "', '" + todoId + "')";
        Object before = db.fetchValue(rows);

        share("WRITE");

        // A row deleted and inserted again sits at a new place in the table.
        assertThat(db.fetchValue(rows)).isNotNull().isEqualTo(before);
    }

    @Test
    void aNewTaskInASharedListArrivesAsItIsNotAsAGrant() {
        share("WRITE");
        bensDevice.pullAll();

        // Anna adds a task. Ben may see it through the list, and its creation in the log
        // carries all of it. An `access_granted` on top made his device pull its whole
        // snapshot again -- once for every task anyone added.
        var newTask = UUID.randomUUID();
        annasDevice.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, newTask, null, Map.of("title", "Fenster putzen", "status", "OPEN")),
                LIST,
                listId));

        var changes = bensDevice.pullAll();
        assertThat(changes)
                .anyMatch(change -> "upsert".equals(change.get("op"))
                        && newTask.toString().equals(change.get("entityId"))
                        && "Fenster putzen".equals(((Map<?, ?>) change.get("fields")).get("title")));
        assertThat(changes).noneMatch(change -> "access_granted".equals(change.get("op")));
    }

    @Test
    void theShareIsInheritedByTheTasks() {
        share("WRITE");

        // Maintaining permissions task by task is unusable in everyday life.
        bensDevice.setLastSeq(0);
        var changes = bensDevice.pullAll();
        assertThat(changes).anyMatch(change -> todoId.toString().equals(change.get("entityId")));

        // And the task's sheet says where it comes from.
        rest.get()
                .uri("/api/v1/items/" + TODO + "/" + todoId + "/shares")
                .headers(ben.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.inheritedFromType")
                .isEqualTo(LIST)
                .jsonPath("$.entries[?(@.source=='INHERITED')].subjectId")
                .isEqualTo(ben.memberId().toString());
    }

    @Test
    @SuppressWarnings("unchecked")
    void checkingOffWorksTheTitleDoesNot() {
        share("CHECK");
        bensDevice.setLastSeq(0);
        bensDevice.pullAll();

        long position = bensDevice.lastSeq();

        // The checkbox works.
        var checkOff = bensDevice.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, todoId, position, Map.of("status", "DONE")), LIST, listId));
        assertThat(checkOff.get(0).get("status")).isEqualTo("applied");

        // The title does not. Otherwise the level could not be expressed, and the wall
        // tablet could either do nothing or delete the list.
        var rename = bensDevice.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, todoId, position, Map.of("title", "Was anderes")), LIST, listId));
        assertThat(rename.get(0).get("status")).isEqualTo("rejected");
        assertThat(rename.get(0).get("code")).isEqualTo("access.field_not_allowed");

        // Both at once: the status goes through, the title comes back with the server's
        // value, so the device puts it back instead of keeping its own.
        var both = bensDevice.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, todoId, bensDevice.lastSeq(), Map.of("status", "OPEN", "title", "Anders")),
                LIST,
                listId));
        assertThat(both.get(0).get("status")).isEqualTo("conflict");
        assertThat((List<Object>) both.get(0).get("conflictFields")).containsExactly("title");
        assertThat((Map<String, Object>) both.get(0).get("serverFields")).containsEntry("title", "Müll rausbringen");
        assertThat(annasState(todoId).get("fields").toString()).contains("status=OPEN", "title=Müll rausbringen");

        // And creating or deleting in the list certainly does not.
        var newTask = bensDevice.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, UUID.randomUUID(), null, Map.of("title", "Meine")), LIST, listId));
        assertThat(newTask.get(0).get("status")).isEqualTo("rejected");
    }

    @Test
    void onlyTheOwnerChangesTheShare() {
        share("WRITE");

        // Write access allows creating, changing and deleting within the container -- NOT
        // changing the share.
        rest.put()
                .uri("/api/v1/items/" + LIST + "/" + listId + "/shares")
                .headers(ben.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("shares", List.of()))
                .exchange()
                .expectStatus()
                .isForbidden()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("access.only_owner_may_share");
    }

    @Test
    void theSheetShowsTheOwnerFirstAndIsReadableForOthers() {
        share("READ");

        rest.get()
                .uri("/api/v1/items/" + LIST + "/" + listId + "/shares")
                .headers(ben.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.entries[0].source")
                .isEqualTo("OWNER")
                .jsonPath("$.entries[0].subjectId")
                .isEqualTo(anna.memberId().toString())
                // Whoever may not change the share still sees the sheet -- read-only.
                // Knowing who sees something is not a privilege.
                .jsonPath("$.mayEdit")
                .isEqualTo(false)
                // And it says what Ben may do -- the app hides editing on read.
                .jsonPath("$.myLevel")
                .isEqualTo("READ");

        rest.get()
                .uri("/api/v1/items/" + LIST + "/" + listId + "/shares")
                .headers(anna.auth())
                .exchange()
                .expectBody()
                .jsonPath("$.myLevel")
                .isEqualTo("WRITE");
    }

    @Test
    void anAssignmentSharesAutomatically() {
        // Whoever assigns a task to Ben thereby shares it with him. Otherwise someone
        // assigns it and the assignee sees nothing.
        assertThat(bensDevice.pullAll()).isEmpty();

        annasDevice.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, todoId, null, Map.of("assignees", List.of(ben.memberId().toString()))),
                LIST,
                listId));

        bensDevice.setLastSeq(0);
        var changes = bensDevice.pullAll();
        assertThat(changes).anyMatch(change -> todoId.toString().equals(change.get("entityId")));

        // With the check-off level, that is: a task that is assigned to someone who cannot
        // check it off is a message, not a task.
        var checkOff = bensDevice.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, todoId, bensDevice.lastSeq(), Map.of("status", "DONE")), LIST, listId));
        assertThat(checkOff.get(0).get("status")).isEqualTo("applied");
    }

    private long versionOf(UUID entityId) {
        return annasDevice.pullSnapshot(500).stream()
                .filter(change -> entityId.toString().equals(change.get("entityId")))
                .map(change -> ((Number) change.get("version")).longValue())
                .findFirst()
                .orElseThrow();
    }

    private Map<String, Object> annasState(UUID entityId) {
        return annasDevice.pullSnapshot(500).stream()
                .filter(change -> entityId.toString().equals(change.get("entityId")))
                .findFirst()
                .orElseThrow();
    }

    /**
     * Knowing an item's ID is not access to it. Without a share or with only READ, a push
     * changes nothing -- not a field, not the list a task is in, not whether it exists.
     */
    private void pushesAreRejected(boolean readShare) {
        long listVersion = versionOf(listId);
        long todoVersion = versionOf(todoId);
        var listBefore = annasState(listId);
        var todoBefore = annasState(todoId);

        UUID bensList = UUID.randomUUID();
        bensDevice.push(SyncClient.mutation(LIST, bensList, null, Map.of("name", "Meins")));

        var rename = bensDevice.push(SyncClient.mutation(LIST, listId, listVersion, Map.of("name", "Übernommen")));
        var move = bensDevice.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, todoId, todoVersion, Map.of("title", "Weg damit")), LIST, bensList));
        var delete = bensDevice.push(SyncClient.deletion(LIST, listId, listVersion));

        for (var result : readShare ? List.of(rename, move, delete) : List.of(rename, move)) {
            assertThat(result.getFirst().get("status")).isEqualTo("rejected");
            assertThat(result.getFirst().get("code"))
                    .isIn("access.denied", readShare ? "access.field_not_allowed" : "access.denied");
        }
        if (!readShare) {
            // Deleting what one cannot see answers like deleting an id that does not
            // exist -- and does nothing, as the state below shows.
            assertThat(delete.getFirst().get("status")).isEqualTo("applied");
        }
        assertThat(annasState(listId)).isEqualTo(listBefore);
        assertThat(annasState(todoId)).isEqualTo(todoBefore);
    }

    @Test
    void withoutAShareNothingIsWritten() {
        pushesAreRejected(false);
    }

    @Test
    void readingIsNotWriting() {
        share("READ");
        pushesAreRejected(true);
    }
}
