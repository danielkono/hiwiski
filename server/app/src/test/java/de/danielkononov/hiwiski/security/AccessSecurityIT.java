package de.danielkononov.hiwiski.security;

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
 * Access rules found missing in a security review, each held to the secure behaviour.
 *
 * <p>Cast: Anna is
 * the admin and owns most items, Ben is the (non-admin) member who tries to do more than
 * his share allows, Carl is a bystander whose view shows whether the sharing changed.
 */
@IntegrationTest
@SuppressWarnings("unchecked")
class AccessSecurityIT {

    private static final String LIST = "TODO_LIST";
    private static final String TODO = "TODO";
    private static final String CALENDAR = "CALENDAR";
    private static final String EVENT = "EVENT";
    private static final String PAGE = "WIKI_PAGE";

    @Autowired RestTestClient rest;
    @Autowired DSLContext db;
    @Autowired org.springframework.context.ApplicationContext context;
    @Autowired org.springframework.transaction.PlatformTransactionManager transactions;

    private Family.Session anna;
    private Family.Session ben;
    private Family.Session carl;
    private SyncClient annasDevice;
    private SyncClient bensDevice;
    private SyncClient carlsDevice;

    @BeforeEach
    void family() {
        anna = Family.setUp(rest);
        ben = invite("Ben", "ben");
        carl = invite("Carl", "carl");
        annasDevice = new SyncClient(rest, anna);
        bensDevice = new SyncClient(rest, ben);
        carlsDevice = new SyncClient(rest, carl);
    }

    // ---------------------------------------------------------------------------------
    // *write* does not delete the container
    // ---------------------------------------------------------------------------------

    @Test
    void writeShareeCannotDeleteTheList() {
        UUID list = create(annasDevice, LIST, Map.of("name", "Household"));
        UUID hidden = createIn(annasDevice, TODO, Map.of("title", "Secret present", "status", "OPEN"), LIST, list);
        share(anna, LIST, list, ben, "WRITE");
        // A direct share replaces the inherited one: Ben cannot see this task.
        share(anna, TODO, hidden, carl, "READ");

        var result = bensDevice.push(SyncClient.deletion(LIST, list, version("todo_list", list)));

        assertThat(result.getFirst().get("status")).isEqualTo("rejected");
        assertThat(deletedAt("todo_list", list)).isNull();
        assertThat(deletedAt("todo", hidden)).isNull();
    }

    @Test
    void writeShareeCannotDeleteTheCalendar() {
        UUID calendar = create(annasDevice, CALENDAR, Map.of("name", "Family", "colorToken", "BLUE", "kind", "LOCAL"));
        UUID event = createIn(annasDevice, EVENT, timed("Dentist"), CALENDAR, calendar);
        share(anna, CALENDAR, calendar, ben, "WRITE");

        var result = bensDevice.push(SyncClient.deletion(CALENDAR, calendar, version("calendar", calendar)));

        assertThat(result.getFirst().get("status")).isEqualTo("rejected");
        assertThat(deletedAt("calendar", calendar)).isNull();
        assertThat(deletedAt("event", event)).isNull();
    }

    @Test
    void writeShareeCannotDeleteTheSharedPageNorASubpageWithAHiddenChild() {
        UUID root = create(annasDevice, PAGE, page("Parents"));
        UUID house = createIn(annasDevice, PAGE, page("House"), PAGE, root);
        UUID secret = createIn(annasDevice, PAGE, page("Finances"), PAGE, house);
        share(anna, PAGE, root, ben, "WRITE");
        share(anna, PAGE, secret, carl, "READ");

        var shared = bensDevice.push(SyncClient.deletion(PAGE, root, version("wiki_page", root)));
        // "House" lies inside what Ben may write, but takes a page with him he cannot see.
        var withHidden = bensDevice.push(SyncClient.deletion(PAGE, house, version("wiki_page", house)));

        assertThat(shared.getFirst().get("status")).isEqualTo("rejected");
        assertThat(withHidden.getFirst().get("status")).isEqualTo("rejected");
        assertThat(deletedAt("wiki_page", secret)).isNull();
    }

    @Test
    void writeShareeStillDeletesWithinTheContainer() {
        UUID list = create(annasDevice, LIST, Map.of("name", "Household"));
        UUID task = createIn(annasDevice, TODO, Map.of("title", "Milk", "status", "OPEN"), LIST, list);
        UUID root = create(annasDevice, PAGE, page("Parents"));
        UUID sub = createIn(annasDevice, PAGE, page("Holidays"), PAGE, root);
        share(anna, LIST, list, ben, "WRITE");
        share(anna, PAGE, root, ben, "WRITE");

        var task1 = bensDevice.push(SyncClient.deletion(TODO, task, version("todo", task)));
        var page1 = bensDevice.push(SyncClient.deletion(PAGE, sub, version("wiki_page", sub)));

        assertThat(task1.getFirst().get("status")).isEqualTo("applied");
        assertThat(page1.getFirst().get("status")).isEqualTo("applied");
    }

    @Test
    void ownerDeletesTheirListWithEverythingInIt() {
        UUID list = create(annasDevice, LIST, Map.of("name", "Household"));
        share(anna, LIST, list, ben, "WRITE");
        // Ben's own task in Anna's list, shared with Carl only: Anna cannot see it.
        UUID bens = createIn(bensDevice, TODO, Map.of("title", "Bens", "status", "OPEN"), LIST, list);
        share(ben, TODO, bens, carl, "READ");

        var result = annasDevice.push(SyncClient.deletion(LIST, list, version("todo_list", list)));

        assertThat(result.getFirst().get("status")).isEqualTo("applied");
        assertThat(deletedAt("todo", bens)).isNotNull();
    }

    @Test
    void writeShareeCannotRestoreTheContainerFromTheTrash() {
        UUID list = create(annasDevice, LIST, Map.of("name", "Household"));
        share(anna, LIST, list, ben, "WRITE");
        annasDevice.push(SyncClient.deletion(LIST, list, version("todo_list", list)));

        var trash = (List<Map<String, Object>>) rest.get()
                .uri("/api/v1/trash")
                .headers(ben.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody()
                .get("entries");
        rest.post()
                .uri("/api/v1/trash/" + LIST + "/" + list + "/restore")
                .headers(ben.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of())
                .exchange()
                .expectStatus()
                .isNotFound();

        assertThat(trash).extracting(item -> item.get("itemId")).doesNotContain(list.toString());
        assertThat(deletedAt("todo_list", list)).isNotNull();
    }

    // ---------------------------------------------------------------------------------
    // *write* does not move another owner's item
    // ---------------------------------------------------------------------------------

    @Test
    void writeShareeCannotMoveAnotherOwnersPageIntoOwnBranch() {
        UUID parents = create(annasDevice, PAGE, page("Parents"));
        UUID finances = createIn(annasDevice, PAGE, page("Finances"), PAGE, parents);
        share(anna, PAGE, parents, ben, "WRITE");
        UUID bensNotes = create(bensDevice, PAGE, page("Bens notes"));
        share(ben, PAGE, bensNotes, carl, "READ");

        var result = bensDevice.push(SyncClient.mutation(
                PAGE, finances, version("wiki_page", finances), Map.of("parentId", bensNotes.toString())));

        assertThat(result.getFirst().get("status")).isEqualTo("rejected");
        assertThat(ids(carlsDevice.pullSnapshot(500))).doesNotContain(finances.toString());
    }

    @Test
    void writeShareeCannotMoveAnotherOwnersPageToRoot() {
        UUID parents = create(annasDevice, PAGE, page("Parents"));
        UUID finances = createIn(annasDevice, PAGE, page("Finances"), PAGE, parents);
        share(anna, PAGE, parents, ben, "WRITE");
        share(anna, PAGE, parents, carl, "READ", ben, "WRITE");

        var toRoot = new java.util.HashMap<String, Object>();
        toRoot.put("parentId", null);
        var result = bensDevice.push(SyncClient.mutation(PAGE, finances, version("wiki_page", finances), toRoot));

        assertThat(result.getFirst().get("status")).isEqualTo("rejected");
        assertThat(ids(carlsDevice.pullSnapshot(500))).contains(finances.toString());
    }

    @Test
    void writeShareeCannotMoveAnotherOwnersEventIntoOwnCalendar() {
        UUID family = create(annasDevice, CALENDAR, Map.of("name", "Family", "colorToken", "BLUE", "kind", "LOCAL"));
        UUID event = createIn(annasDevice, EVENT, timed("Therapy"), CALENDAR, family);
        share(anna, CALENDAR, family, ben, "WRITE");
        UUID bens = create(bensDevice, CALENDAR, Map.of("name", "Bens", "colorToken", "RED", "kind", "LOCAL"));
        share(ben, CALENDAR, bens, carl, "READ");

        var result = bensDevice.push(SyncClient.mutation(
                EVENT, event, version("event", event), Map.of("calendarId", bens.toString())));
        unshare(anna, CALENDAR, family);

        assertThat(result.getFirst().get("status")).isEqualTo("rejected");
        assertThat(ids(carlsDevice.pullSnapshot(500))).doesNotContain(event.toString());
        assertThat(ids(bensDevice.pullSnapshot(500))).doesNotContain(event.toString());
    }

    @Test
    void ownerStillMovesTheirOwnItemAndWriterEditsInPlace() {
        UUID family = create(annasDevice, CALENDAR, Map.of("name", "Family", "colorToken", "BLUE", "kind", "LOCAL"));
        UUID work = create(annasDevice, CALENDAR, Map.of("name", "Work", "colorToken", "RED", "kind", "LOCAL"));
        UUID event = createIn(annasDevice, EVENT, timed("Therapy"), CALENDAR, family);
        share(anna, CALENDAR, family, ben, "WRITE");

        var edit = bensDevice.push(SyncClient.mutation(
                EVENT, event, version("event", event), Map.of("title", "Therapy (moved to 9)")));
        var move = annasDevice.push(SyncClient.mutation(
                EVENT, event, version("event", event), Map.of("calendarId", work.toString())));

        assertThat(edit.getFirst().get("status")).isEqualTo("applied");
        assertThat(move.getFirst().get("status")).isEqualTo("applied");
    }

    // ---------------------------------------------------------------------------------
    // Assignments do not share beyond what the owner shared
    // ---------------------------------------------------------------------------------

    @Test
    void writeShareeCannotShareTheListByAssigningAGroup() {
        UUID list = create(annasDevice, LIST, Map.of("name", "Christmas presents"));
        createIn(annasDevice, TODO, Map.of("title", "Bike for Carl", "status", "OPEN"), LIST, list);
        share(anna, LIST, list, ben, "WRITE");

        var result = bensDevice.push(SyncClient.mutation(
                LIST, list, version("todo_list", list), Map.of("assignees", List.of(groupId("Everyone").toString()))));

        assertThat(result.getFirst().get("status")).isNotEqualTo("applied");
        assertThat(ids(carlsDevice.pullSnapshot(500))).doesNotContain(list.toString());
        assertThat(level(carl, LIST, list)).isNull();
    }

    @Test
    void selfAssignmentDoesNotOutliveARevokedShare() {
        UUID list = create(annasDevice, LIST, Map.of("name", "Household"));
        UUID task = createIn(annasDevice, TODO, Map.of("title", "Bins", "status", "OPEN"), LIST, list);
        UUID calendar = create(annasDevice, CALENDAR, Map.of("name", "Family", "colorToken", "BLUE", "kind", "LOCAL"));
        UUID event = createIn(annasDevice, EVENT, timed("Dinner"), CALENDAR, calendar);
        share(anna, LIST, list, ben, "WRITE");
        share(anna, CALENDAR, calendar, ben, "WRITE");
        String me = ben.memberId().toString();
        bensDevice.push(SyncClient.mutation(LIST, list, version("todo_list", list), Map.of("assignees", List.of(me))));
        var onTask = bensDevice.push(
                SyncClient.mutation(TODO, task, version("todo", task), Map.of("assignees", List.of(me))));
        var onEvent = bensDevice.push(
                SyncClient.mutation(EVENT, event, version("event", event), Map.of("attendees", List.of(me))));
        assertThat(onTask.getFirst().get("status")).isEqualTo("applied");
        assertThat(onEvent.getFirst().get("status")).isEqualTo("applied");

        unshare(anna, LIST, list);
        unshare(anna, CALENDAR, calendar);

        assertThat(level(ben, LIST, list)).isNull();
        assertThat(level(ben, TODO, task)).isNull();
        assertThat(level(ben, EVENT, event)).isNull();
    }

    @Test
    void writersAssignmentRaisesWithinTheAudienceOnly() {
        UUID list = create(annasDevice, LIST, Map.of("name", "Household"));
        UUID task = createIn(annasDevice, TODO, Map.of("title", "Bins", "status", "OPEN"), LIST, list);
        share(anna, LIST, list, ben, "WRITE", carl, "READ");
        var dana = invite("Dana", "dana");

        var result = bensDevice.push(SyncClient.mutation(TODO, task, version("todo", task), Map.of(
                "assignees", List.of(carl.memberId().toString(), dana.memberId().toString()))));

        assertThat(result.getFirst().get("status")).isEqualTo("applied");
        assertThat(level(carl, TODO, task)).isEqualTo("CHECK");
        assertThat(level(dana, TODO, task)).isNull();
    }

    @Test
    void ownersAssignmentStillShares() {
        UUID list = create(annasDevice, LIST, Map.of("name", "Annas"));
        UUID task = createIn(annasDevice, TODO, Map.of("title", "Homework", "status", "OPEN"), LIST, list);

        annasDevice.push(SyncClient.mutation(
                TODO, task, version("todo", task), Map.of("assignees", List.of(carl.memberId().toString()))));
        // A later edit by someone else keeps the owner's choice.
        share(anna, LIST, list, ben, "WRITE");
        bensDevice.push(SyncClient.mutation(TODO, task, version("todo", task), Map.of("title", "Maths homework")));

        assertThat(level(carl, TODO, task)).isEqualTo("CHECK");
    }

    // ---------------------------------------------------------------------------------
    // Boards and feeds are not shared, and their tokens stay with the owner
    // ---------------------------------------------------------------------------------

    @Test
    void boardAndFeedCannotBeShared() {
        UUID board = UUID.randomUUID();
        annasDevice.push(SyncClient.mutation("BOARD", board, null, Map.of(
                "kind", "DASHBOARD", "name", "Kitchen", "layout", "GRID", "columns", 4, "token", token())));
        UUID calendar = create(annasDevice, CALENDAR, Map.of("name", "Family", "colorToken", "BLUE", "kind", "LOCAL"));
        UUID feed = create(annasDevice, "CALENDAR_FEED", Map.of(
                "name", "Phone", "calendarIds", List.of(calendar.toString()), "contentMode", "FULL", "token", token()));

        for (var item : List.of(Map.entry("BOARD", board), Map.entry("CALENDAR_FEED", feed))) {
            var body = rest.put()
                    .uri("/api/v1/items/" + item.getKey() + "/" + item.getValue() + "/shares")
                    .headers(anna.auth())
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(Map.of("shares", List.of(Map.of(
                            "subjectType", "MEMBER", "subjectId", ben.memberId().toString(), "level", "READ"))))
                    .exchange()
                    .expectStatus()
                    .isBadRequest()
                    .expectBody(Map.class)
                    .returnResult()
                    .getResponseBody();
            assertThat(body.get("code")).isEqualTo("access.not_shareable");
        }
        assertThat(ids(bensDevice.pullSnapshot(500))).doesNotContain(board.toString(), feed.toString());
    }

    @Test
    void aBoardSharedBeforeTheFixLosesItsShareAndNeverShowsItsToken() {
        UUID board = UUID.randomUUID();
        annasDevice.push(SyncClient.mutation("BOARD", board, null, Map.of(
                "kind", "DASHBOARD", "name", "Kitchen", "layout", "GRID", "columns", 4, "token", token())));
        // As an older server let it happen: a share row written directly.
        db.execute(
                "insert into share (item_type, item_id, subject_type, subject_id, level, created_by)"
                        + " values ('BOARD', ?, 'MEMBER', ?, 'WRITE', ?)",
                board,
                ben.memberId(),
                anna.memberId());
        db.execute(
                "insert into effective_access (member_id, item_type, item_id, level, source)"
                        + " values (?, 'BOARD', ?, 'WRITE', 'DIRECT')",
                ben.memberId(),
                board);

        // Even while the stale row exists, the token does not travel to Ben.
        var bensBoard = bensDevice.pullSnapshot(500).stream()
                .filter(change -> board.toString().equals(change.get("entityId")))
                .findFirst();
        assertThat(bensBoard).isPresent();
        assertThat((Map<String, Object>) bensBoard.get().get("fields")).doesNotContainKey("token");
        var rotate = bensDevice.push(
                SyncClient.mutation("BOARD", board, version("board", board), Map.of("token", token())));
        assertThat(rotate.getFirst().get("status")).isEqualTo("rejected");

        // What the server does once at start.
        Object access = org.springframework.test.util.AopTestUtils.getTargetObject(context.getBean("accessService"));
        new org.springframework.transaction.support.TransactionTemplate(transactions)
                .executeWithoutResult(status ->
                        org.springframework.test.util.ReflectionTestUtils.invokeMethod(access, "dropUnshareable"));

        assertThat(level(ben, "BOARD", board)).isNull();
        var annasBoard = annasDevice.pullSnapshot(500).stream()
                .filter(change -> board.toString().equals(change.get("entityId")))
                .findFirst()
                .orElseThrow();
        assertThat((Map<String, Object>) annasBoard.get("fields")).containsKey("token");
    }

    // ---------------------------------------------------------------------------------
    // No revival without the right to restore; deleted children follow shares
    // ---------------------------------------------------------------------------------

    @Test
    void checkOffCannotReviveADeletedTask() {
        UUID list = create(annasDevice, LIST, Map.of("name", "Shopping"));
        UUID task = createIn(annasDevice, TODO, Map.of("title", "Milk", "status", "OPEN"), LIST, list);
        share(anna, LIST, list, carl, "CHECK");
        annasDevice.push(SyncClient.deletion(TODO, task, version("todo", task)));

        var result = carlsDevice.push(SyncClient.mutation(TODO, task, Long.MAX_VALUE / 2, Map.of("status", "DONE")));

        assertThat(result.getFirst().get("status")).isEqualTo("rejected");
        assertThat(result.getFirst().get("code")).isEqualTo("sync.entity_deleted");
        assertThat(deletedAt("todo", task)).isNotNull();
    }

    @Test
    void writerStillRevivesWhatTheyEditedOffline() {
        UUID list = create(annasDevice, LIST, Map.of("name", "Shopping"));
        UUID task = createIn(annasDevice, TODO, Map.of("title", "Milk", "status", "OPEN"), LIST, list);
        share(anna, LIST, list, ben, "WRITE");
        long before = version("todo", task);
        annasDevice.push(SyncClient.deletion(TODO, task, before));

        var result = bensDevice.push(SyncClient.mutation(TODO, task, before, Map.of("title", "Oat milk")));

        assertThat(result.getFirst().get("status")).isEqualTo("applied");
        assertThat(deletedAt("todo", task)).isNull();
    }

    @Test
    void revokedWriterLosesAccessToDeletedTasksToo() {
        UUID list = create(annasDevice, LIST, Map.of("name", "Household"));
        UUID task = createIn(annasDevice, TODO, Map.of("title", "Bins", "status", "OPEN"), LIST, list);
        share(anna, LIST, list, ben, "WRITE");
        annasDevice.push(SyncClient.deletion(TODO, task, version("todo", task)));

        unshare(anna, LIST, list);
        var result = bensDevice.push(SyncClient.mutation(TODO, task, Long.MAX_VALUE / 2, Map.of("title", "Mine now")));

        assertThat(level(ben, TODO, task)).isNull();
        assertThat(result.getFirst().get("status")).isEqualTo("rejected");
        assertThat(deletedAt("todo", task)).isNotNull();
    }

    // ---------------------------------------------------------------------------------
    // A comment needs read access to the carrier of the type it names
    // ---------------------------------------------------------------------------------

    @Test
    void cannotCommentOnAnUnreadablePageThroughASameIdListOfOwn() {
        UUID secret = create(annasDevice, PAGE, page("Annas private page"));
        // Ben's own list with the very same id (ids are client-chosen, tables differ).
        var squat = bensDevice.push(SyncClient.mutation(LIST, secret, null, Map.of("name", "Decoy")));
        assertThat(squat.getFirst().get("status")).isEqualTo("applied");

        UUID comment = UUID.randomUUID();
        var result = bensDevice.push(SyncClient.withContainer(
                SyncClient.mutation("COMMENT", comment, null, Map.of(
                        "itemType", PAGE, "itemId", secret.toString(), "body", "Ben was here")),
                PAGE,
                secret));

        assertThat(result.getFirst().get("status")).isEqualTo("rejected");
        assertThat(ids(annasDevice.pullSnapshot(500))).doesNotContain(comment.toString());
    }

    @Test
    void aReaderStillComments() {
        UUID shared = create(annasDevice, PAGE, page("Holidays"));
        share(anna, PAGE, shared, ben, "READ");

        var result = bensDevice.push(SyncClient.withContainer(
                SyncClient.mutation("COMMENT", UUID.randomUUID(), null, Map.of(
                        "itemType", PAGE, "itemId", shared.toString(), "body", "Spain?")),
                PAGE,
                shared));

        assertThat(result.getFirst().get("status")).isEqualTo("applied");
    }

    // ---------------------------------------------------------------------------------
    // Input limits on sync push
    // ---------------------------------------------------------------------------------

    @Test
    void tooManyMutationsInOnePushAreRefused() {
        var mutations = new java.util.ArrayList<Map<String, Object>>();
        for (int i = 0; i < 201; i++) {
            mutations.add(SyncClient.mutation(LIST, UUID.randomUUID(), null, Map.of("name", "L" + i)));
        }

        rest.post()
                .uri("/api/v1/sync/push")
                .headers(ben.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("deviceId", ben.deviceId().toString(), "pendingCount", 201, "mutations", mutations))
                .exchange()
                .expectStatus()
                .isBadRequest();
        assertThat(db.fetchCount(db.selectFrom("todo_list").where("owner_id = ?", ben.memberId()))).isZero();
    }

    @Test
    void oversizedValuesRejectTheirMutationOnly() {
        UUID list = create(bensDevice, LIST, Map.of("name", "Bens"));
        var manyIds = java.util.stream.IntStream.range(0, 501)
                .mapToObj(i -> UUID.randomUUID().toString())
                .toList();

        var results = bensDevice.push(
                SyncClient.mutation(PAGE, UUID.randomUUID(), null, Map.of(
                        "title", "Huge", "kind", "PAGE", "content", "x".repeat(200_001))),
                SyncClient.withContainer(
                        SyncClient.mutation(TODO, UUID.randomUUID(), null, Map.of(
                                "title", "Tagged", "status", "OPEN", "tags", manyIds)),
                        LIST,
                        list),
                SyncClient.mutation(PAGE, UUID.randomUUID(), null, page("Fine")));

        assertThat(results).extracting(result -> result.get("status"))
                .containsExactly("rejected", "rejected", "applied");
        assertThat(results.get(0).get("code")).isEqualTo("sync.value_too_large");
        assertThat(results.get(1).get("code")).isEqualTo("sync.value_too_large");
    }

    @Test
    void anOversizedBodyIsRefusedBeforeItIsRead() {
        rest.post()
                .uri("/api/v1/sync/push")
                .headers(ben.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(oversized())
                .exchange()
                .expectStatus()
                .isEqualTo(413);
    }

    // ---------------------------------------------------------------------------------
    // Malformed pushes are rejections, not server errors
    // ---------------------------------------------------------------------------------

    @Test
    void nullBoardLayoutIsRejectedNotAServerError() {
        var fields = new java.util.HashMap<String, Object>();
        fields.put("kind", "DASHBOARD");
        fields.put("name", "Hall");
        fields.put("layout", null);

        var result = bensDevice.push(SyncClient.mutation("BOARD", UUID.randomUUID(), null, fields));

        assertThat(result.getFirst().get("status")).isEqualTo("rejected");
        assertThat(result.getFirst().get("code")).isEqualTo("dashboard.layout_invalid");
    }

    @Test
    void nullAssigneeIsRejectedNotAServerError() {
        UUID list = create(bensDevice, LIST, Map.of("name", "Bens"));

        var result = bensDevice.push(SyncClient.withContainer(
                SyncClient.mutation(TODO, UUID.randomUUID(), null, Map.of(
                        "title", "x", "status", "OPEN", "assignees", java.util.Arrays.asList((Object) null))),
                LIST,
                list));

        assertThat(result.getFirst().get("status")).isEqualTo("rejected");
        assertThat(result.getFirst().get("code")).isEqualTo("sync.invalid_field");
    }

    // ---------------------------------------------------------------------------------
    // An unseen id answers like an unknown one
    // ---------------------------------------------------------------------------------

    @Test
    void deleteOfAnUnseenItemLooksLikeAnUnknownId() {
        UUID secret = create(annasDevice, LIST, Map.of("name", "Annas secret list"));

        var unseen = bensDevice.push(SyncClient.deletion(LIST, secret, 1L)).getFirst();
        var unknown = bensDevice.push(SyncClient.deletion(LIST, UUID.randomUUID(), 1L)).getFirst();

        assertThat(List.of(unseen.get("status"), String.valueOf(unseen.get("code"))))
                .isEqualTo(List.of(unknown.get("status"), String.valueOf(unknown.get("code"))));
        assertThat(deletedAt("todo_list", secret)).isNull();
    }

    @Test
    void sharesOfAnUnseenItemAnswerLikeAnUnknownId() {
        UUID secret = create(annasDevice, PAGE, page("Private"));
        UUID seen = create(annasDevice, PAGE, page("Shared"));
        share(anna, PAGE, seen, ben, "READ");

        for (UUID id : List.of(secret, UUID.randomUUID())) {
            rest.put()
                    .uri("/api/v1/items/" + PAGE + "/" + id + "/shares")
                    .headers(ben.auth())
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(Map.of("shares", List.of()))
                    .exchange()
                    .expectStatus()
                    .isNotFound();
        }
        // Seeing it but not owning it is still a 403 -- that tells nothing new.
        rest.put()
                .uri("/api/v1/items/" + PAGE + "/" + seen + "/shares")
                .headers(ben.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("shares", List.of()))
                .exchange()
                .expectStatus()
                .isForbidden();
    }

    // ---------------------------------------------------------------------------------
    // A list order carries its member's own id
    // ---------------------------------------------------------------------------------

    @Test
    void cannotSquatAnotherMembersListOrder() {
        var squat = bensDevice.push(SyncClient.mutation("LIST_ORDER", carl.memberId(), null, Map.of("listIds", List.of())));
        var own = carlsDevice.push(SyncClient.mutation(
                "LIST_ORDER", carl.memberId(), null, Map.of("listIds", List.of(UUID.randomUUID().toString()))));

        assertThat(squat.getFirst().get("status")).isEqualTo("rejected");
        assertThat(own.getFirst().get("status")).isEqualTo("applied");
    }

    // ---------------------------------------------------------------------------------
    // The ICS feed publishes only what its owner may see, while they may
    // ---------------------------------------------------------------------------------

    @Test
    void feedLeavesOutEventsTheOwnerCannotSeeAndStopsForADisabledOwner() {
        UUID family = create(annasDevice, CALENDAR, Map.of("name", "Family", "colorToken", "BLUE", "kind", "LOCAL"));
        createIn(annasDevice, EVENT, timed("Annas dentist"), CALENDAR, family);
        share(anna, CALENDAR, family, ben, "WRITE");
        UUID bens = createIn(bensDevice, EVENT, timed("Surprise party planning"), CALENDAR, family);
        // Ben's own event, shared with Carl only: Anna does not see it.
        share(ben, EVENT, bens, carl, "READ");
        String token = token();
        create(annasDevice, "CALENDAR_FEED", Map.of(
                "name", "Phone", "calendarIds", List.of(family.toString()), "contentMode", "FULL", "token", token));

        String ics = rest.get()
                .uri("/ics/" + token + ".ics")
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(String.class)
                .returnResult()
                .getResponseBody();
        assertThat(ics).contains("Annas dentist").doesNotContain("Surprise party");

        db.execute("update member set disabled_at = now() where id = ?", anna.memberId());
        rest.get().uri("/ics/" + token + ".ics").exchange().expectStatus().isNotFound();
    }

    // ---------------------------------------------------------------------------------
    // Imports match only what the importer may write; refresh stops without WRITE
    // ---------------------------------------------------------------------------------

    private static String ics(String summary) {
        return "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n"
                + "BEGIN:VEVENT\r\nUID:u1@example.org\r\nDTSTAMP:20260901T000000Z\r\n"
                + "DTSTART:20261013T170000Z\r\nDTEND:20261013T190000Z\r\nSUMMARY:" + summary + "\r\n"
                + "END:VEVENT\r\nEND:VCALENDAR\r\n";
    }

    private void importInto(Family.Session who, UUID calendar, String ics) {
        rest.post()
                .uri("/api/v1/calendars/" + calendar + "/import")
                .headers(who.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("ics", ics))
                .exchange()
                .expectStatus()
                .isOk();
    }

    @Test
    void importDoesNotOverwriteAnEventTheImporterMayNotWrite() {
        UUID family = create(annasDevice, CALENDAR, Map.of("name", "Family", "colorToken", "BLUE", "kind", "LOCAL"));
        importInto(anna, family, ics("Annas appointment"));
        UUID event = (UUID) db.fetchValue("select id from event where source_uid = 'u1@example.org'");
        share(anna, CALENDAR, family, ben, "WRITE");
        // Anna's event gets a share of its own that leaves Ben out.
        share(anna, EVENT, event, carl, "READ");

        importInto(ben, family, ics("Overwritten by Ben"));

        assertThat(db.fetchValue("select title from event where id = ?", event)).isEqualTo("Annas appointment");
    }

    @Test
    void refreshStopsWhenTheSubscriptionsOwnerLostWrite() {
        UUID family = create(annasDevice, CALENDAR, Map.of("name", "Family", "colorToken", "BLUE", "kind", "LOCAL"));
        share(anna, CALENDAR, family, ben, "WRITE");
        // Attached before sync refused a subscription in someone else's calendar: such rows may still exist.
        UUID subscription = UUID.randomUUID();
        db.execute(
                "insert into calendar_subscription (id, owner_id, version, calendar_id, name, url) "
                        + "values (?, ?, 1, ?, 'Bens feed', 'https://example.invalid/feed.ics')",
                subscription,
                ben.memberId(),
                family);
        unshare(anna, CALENDAR, family);

        var result = rest.post()
                .uri("/api/v1/calendar/subscriptions/" + subscription + "/refresh")
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();

        assertThat(result.get("ok")).isEqualTo(false);
        assertThat(result.get("error")).isEqualTo("calendar.subscription_read_only");
    }

    // ---------------------------------------------------------------------------------
    // Check off ticks off occurrences of a series
    // ---------------------------------------------------------------------------------

    @Test
    void checkOffTicksAndUnticksAnOccurrenceReadDoesNot() {
        UUID list = create(annasDevice, LIST, Map.of("name", "Chores"));
        UUID task = createIn(annasDevice, TODO, Map.of(
                "title", "Water the plants", "status", "OPEN", "dueDate", "2026-11-02", "rrule", "FREQ=WEEKLY"),
                LIST, list);
        share(anna, LIST, list, carl, "CHECK", ben, "READ");
        Map<String, Object> tick = Map.of("occurrenceDate", "2026-11-02", "doneAt", "2026-11-02T09:00:00Z");

        UUID occurrence = UUID.randomUUID();
        var ticked = carlsDevice.push(SyncClient.withContainer(
                SyncClient.mutation("TODO_OCCURRENCE", occurrence, null, tick), TODO, task));
        var unticked = carlsDevice.push(
                SyncClient.deletion("TODO_OCCURRENCE", occurrence, version("todo_occurrence", occurrence)));
        var reader = bensDevice.push(SyncClient.withContainer(
                SyncClient.mutation("TODO_OCCURRENCE", UUID.randomUUID(), null, tick), TODO, task));

        assertThat(ticked.getFirst().get("status")).isEqualTo("applied");
        assertThat(unticked.getFirst().get("status")).isEqualTo("applied");
        assertThat(deletedAt("todo_occurrence", occurrence)).isNotNull();
        assertThat(reader.getFirst().get("status")).isEqualTo("rejected");
    }

    // ---------------------------------------------------------------------------------
    // Who did it, and when, is the server's to say
    // ---------------------------------------------------------------------------------

    @Test
    void doneByAndArchivedByAreTheActorAndDoneAtIsNotInTheFuture() {
        UUID list = create(annasDevice, LIST, Map.of("name", "Chores"));
        UUID task = createIn(annasDevice, TODO, Map.of(
                "title", "Plants", "status", "OPEN", "dueDate", "2026-11-02", "rrule", "FREQ=WEEKLY"), LIST, list);
        share(anna, LIST, list, carl, "CHECK", ben, "WRITE");

        UUID occurrence = UUID.randomUUID();
        carlsDevice.push(SyncClient.withContainer(
                SyncClient.mutation("TODO_OCCURRENCE", occurrence, null, Map.of(
                        "occurrenceDate", "2026-11-02",
                        "doneAt", "2999-01-01T00:00:00Z",
                        "doneBy", anna.memberId().toString())),
                TODO,
                task));
        UUID page = create(bensDevice, PAGE, page("Old notes"));
        bensDevice.push(SyncClient.mutation(PAGE, page, version("wiki_page", page), Map.of(
                "archivedAt", "2026-10-01T00:00:00Z", "archivedBy", anna.memberId().toString())));

        assertThat(db.fetchValue("select done_by from todo_occurrence where id = ?", occurrence))
                .isEqualTo(carl.memberId());
        assertThat((java.time.OffsetDateTime) db.fetchValue("select done_at from todo_occurrence where id = ?", occurrence))
                .isBefore(java.time.OffsetDateTime.now().plusMinutes(1));
        assertThat(db.fetchValue("select archived_by from wiki_page where id = ?", page)).isEqualTo(ben.memberId());
        assertThat(db.fetchValue("select archived_at from wiki_page where id = ?", page).toString()).startsWith("2026-10-01");
    }

    // ---------------------------------------------------------------------------------
    // A calendar feed's token is long and random
    // ---------------------------------------------------------------------------------

    @Test
    void weakFeedTokensAreRefusedAndNotServed() {
        UUID calendar = create(annasDevice, CALENDAR, Map.of("name", "Family", "colorToken", "BLUE", "kind", "LOCAL"));
        Map<String, Object> feed = Map.of(
                "name", "Phone", "calendarIds", List.of(calendar.toString()), "contentMode", "FULL", "token", "1");

        var weak = annasDevice.push(SyncClient.mutation("CALENDAR_FEED", UUID.randomUUID(), null, feed));
        // One written before the server checked.
        db.execute(
                "insert into calendar_feed (id, owner_id, version, name, calendar_ids, content_mode, token)"
                        + " values (?, ?, 1, 'Old', ?, 'FULL', 'short')",
                UUID.randomUUID(),
                anna.memberId(),
                new UUID[] {calendar});

        assertThat(weak.getFirst().get("status")).isEqualTo("rejected");
        assertThat(weak.getFirst().get("code")).isEqualTo("calendar.feed_token_invalid");
        rest.get().uri("/ics/short.ics").exchange().expectStatus().isNotFound();
    }

    // ---------------------------------------------------------------------------------
    // Subscribed and locked imported calendars are read-only on the sync path too
    // ---------------------------------------------------------------------------------

    @Test
    void lockedCalendarTakesOnlyLocalAdditions() {
        UUID external = create(annasDevice, CALENDAR, Map.of("name", "School", "colorToken", "BLUE", "kind", "EXTERNAL"));
        share(anna, CALENDAR, external, ben, "WRITE");
        importLocked(external);
        UUID event = (UUID) db.fetchValue("select id from event where calendar_id = ?", external);

        var retitle = bensDevice.push(SyncClient.mutation(EVENT, event, version("event", event), Map.of("title", "Fake")));
        var added = bensDevice.push(SyncClient.withContainer(
                SyncClient.mutation(EVENT, UUID.randomUUID(), null, timed("Forged")), CALENDAR, external));
        var unlock = bensDevice.push(
                SyncClient.mutation(CALENDAR, external, version("calendar", external), Map.of("kind", "LOCAL")));
        var reminder = annasDevice.push(
                SyncClient.mutation(EVENT, event, version("event", event), Map.of("reminderMinutes", 30)));

        assertThat(List.of(retitle, added, unlock))
                .allSatisfy(result -> assertThat(result.getFirst().get("code")).isEqualTo("calendar.read_only"));
        assertThat(reminder.getFirst().get("status")).isEqualTo("applied");
        assertThat(db.fetchValue("select title from event where id = ?", event)).isEqualTo("Parents' evening");
    }

    /** One event in the calendar, written the way a refresh writes it -- as a server write. */
    private void importLocked(UUID calendar) {
        Object subscriptions =
                org.springframework.test.util.AopTestUtils.getTargetObject(context.getBean("subscriptionService"));
        new org.springframework.transaction.support.TransactionTemplate(transactions)
                .executeWithoutResult(status -> org.springframework.test.util.ReflectionTestUtils.invokeMethod(
                        subscriptions, "importFile", calendar, anna.memberId(), ics("Parents' evening")));
    }

    /** A JSON body of 33 MiB: an object padded with spaces. */
    private static byte[] oversized() {
        byte[] body = new byte[33 * 1024 * 1024];
        java.util.Arrays.fill(body, (byte) ' ');
        body[0] = '{';
        body[body.length - 1] = '}';
        return body;
    }

    private static String token() {
        return UUID.randomUUID().toString().replace("-", "");
    }

    // ---------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------

    private static Map<String, Object> page(String title) {
        return Map.of("title", title, "kind", "PAGE", "content", "");
    }

    private static Map<String, Object> timed(String title) {
        return Map.of("title", title, "timeForm", "TIMED", "startsAt", "2026-11-12T08:00:00Z");
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
                        "device", Map.of("deviceName", displayName + "s Tablet", "platform", "ANDROID")))
                .exchange()
                .expectStatus()
                .is2xxSuccessful()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody());
    }

    private UUID groupId(String name) {
        var groups = (List<Map<String, Object>>) rest.get()
                .uri("/api/v1/groups")
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody()
                .get("groups");
        return groups.stream()
                .filter(group -> name.equals(group.get("name")))
                .map(group -> UUID.fromString((String) group.get("id")))
                .findFirst()
                .orElseThrow();
    }

    private static UUID create(SyncClient device, String type, Map<String, Object> fields) {
        UUID id = UUID.randomUUID();
        var result = device.push(SyncClient.mutation(type, id, null, fields));
        assertThat(result.getFirst().get("status")).as("setup: create %s %s", type, result).isEqualTo("applied");
        return id;
    }

    private static UUID createIn(
            SyncClient device, String type, Map<String, Object> fields, String containerType, UUID containerId) {
        UUID id = UUID.randomUUID();
        var result = device.push(SyncClient.withContainer(
                SyncClient.mutation(type, id, null, fields), containerType, containerId));
        assertThat(result.getFirst().get("status")).as("setup: create %s %s", type, result).isEqualTo("applied");
        return id;
    }

    private void share(Family.Session owner, String type, UUID id, Family.Session with, String level) {
        putShares(owner, type, id, List.of(Map.of(
                "subjectType", "MEMBER", "subjectId", with.memberId().toString(), "level", level)));
    }

    private void share(
            Family.Session owner,
            String type,
            UUID id,
            Family.Session first,
            String firstLevel,
            Family.Session second,
            String secondLevel) {
        putShares(owner, type, id, List.of(
                Map.of("subjectType", "MEMBER", "subjectId", first.memberId().toString(), "level", firstLevel),
                Map.of("subjectType", "MEMBER", "subjectId", second.memberId().toString(), "level", secondLevel)));
    }

    private void unshare(Family.Session owner, String type, UUID id) {
        putShares(owner, type, id, List.of());
    }

    private void putShares(Family.Session owner, String type, UUID id, List<Map<String, Object>> shares) {
        rest.put()
                .uri("/api/v1/items/" + type + "/" + id + "/shares")
                .headers(owner.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("shares", shares))
                .exchange()
                .expectStatus()
                .isOk();
    }

    private long version(String table, UUID id) {
        return ((Number) db.fetchValue("select version from " + table + " where id = ?", id)).longValue();
    }

    private Object deletedAt(String table, UUID id) {
        return db.fetchValue("select deleted_at from " + table + " where id = ?", id);
    }

    private String level(Family.Session who, String type, UUID id) {
        return (String) db.fetchValue(
                "select level from effective_access where member_id = ? and item_type = ? and item_id = ?",
                who.memberId(),
                type,
                id);
    }

    private static List<String> ids(List<Map<String, Object>> changes) {
        return changes.stream().map(change -> String.valueOf(change.get("entityId"))).toList();
    }
}
