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
 * <p>Cast as in
 * {@link AccessSecurityIT}: Anna is the admin and owns most items, Ben may write some of
 * them, Carl is a bystander whose view shows whether the sharing changed.
 */
@IntegrationTest
@SuppressWarnings("unchecked")
class AccessFollowUpIT {

    private static final String LIST = "TODO_LIST";
    private static final String TODO = "TODO";
    private static final String CALENDAR = "CALENDAR";
    private static final String EVENT = "EVENT";

    @Autowired RestTestClient rest;
    @Autowired DSLContext db;
    @Autowired org.springframework.context.ApplicationContext context;
    @Autowired org.springframework.transaction.PlatformTransactionManager transactions;

    private Family.Session anna;
    private Family.Session ben;
    private Family.Session carl;
    private SyncClient annasDevice;
    private SyncClient bensDevice;

    @BeforeEach
    void family() {
        anna = Family.setUp(rest);
        ben = invite("Ben", "ben");
        carl = invite("Carl", "carl");
        annasDevice = new SyncClient(rest, anna);
        bensDevice = new SyncClient(rest, ben);
    }

    // ---------------------------------------------------------------------------------
    // The owner's unrelated write does not adopt a writer's assignment
    // ---------------------------------------------------------------------------------

    @Test
    void ownersTickAndRenameDoNotAdoptAWritersAssignment() {
        UUID list = create(annasDevice, LIST, Map.of("name", "Presents"));
        UUID bike = createIn(annasDevice, TODO, Map.of("title", "Bike for Carl", "status", "OPEN"), LIST, list);
        UUID bins = createIn(annasDevice, TODO, Map.of("title", "Bins", "status", "OPEN"), LIST, list);
        share(anna, LIST, list, ben, "WRITE");
        push(bensDevice, TODO, bike, Map.of("assignees", List.of(carl.memberId().toString())));
        push(bensDevice, TODO, bins, Map.of("assignees", List.of(ben.memberId().toString())));

        push(annasDevice, TODO, bike, Map.of("status", "DONE"));
        push(annasDevice, TODO, bins, Map.of("title", "Bins on Tuesday"));
        unshare(anna, LIST, list);

        assertThat(level(carl, TODO, bike)).isNull();
        assertThat(level(ben, TODO, bins)).isNull();
    }

    @Test
    void ownersEditOfAnotherFieldDoesNotAdoptAWritersAttendee() {
        UUID calendar = create(annasDevice, CALENDAR, Map.of("name", "Family", "colorToken", "BLUE", "kind", "LOCAL"));
        UUID event = createIn(annasDevice, EVENT, timed("Dinner"), CALENDAR, calendar);
        share(anna, CALENDAR, calendar, ben, "WRITE");
        push(bensDevice, EVENT, event, Map.of(
                "attendees", List.of(ben.memberId().toString(), carl.memberId().toString())));

        push(annasDevice, EVENT, event, Map.of("title", "Dinner at Grandma's"));
        unshare(anna, CALENDAR, calendar);

        assertThat(level(carl, EVENT, event)).isNull();
        assertThat(level(ben, EVENT, event)).isNull();
    }

    @Test
    void aSubscriptionRefreshInTheOwnersNameAdoptsNoAttendee() {
        UUID school = create(annasDevice, CALENDAR, Map.of("name", "School", "colorToken", "BLUE", "kind", "EXTERNAL"));
        share(anna, CALENDAR, school, ben, "WRITE");
        UUID subscription = createIn(annasDevice, "CALENDAR_SUBSCRIPTION", Map.of(
                "name", "School", "url", "https://example.invalid/school.ics", "targetKind", "EVENT",
                "syncInterval", "HOURLY"), CALENDAR, school);
        refresh(subscription, school);
        UUID event = (UUID) db.fetchValue("select id from event where calendar_id = ?", school);
        var added = push(bensDevice, EVENT, event, Map.of(
                "attendees", List.of(ben.memberId().toString(), carl.memberId().toString())));
        assertThat(added.getFirst().get("status")).isEqualTo("applied");

        refresh(subscription, school);
        unshare(anna, CALENDAR, school);

        assertThat(level(carl, EVENT, event)).isNull();
        assertThat(level(ben, EVENT, event)).isNull();
    }

    @Test
    void aRestoreFromTheTrashAdoptsNoAssignment() {
        UUID list = create(annasDevice, LIST, Map.of("name", "Presents"));
        UUID bike = createIn(annasDevice, TODO, Map.of("title", "Bike for Carl", "status", "OPEN"), LIST, list);
        share(anna, LIST, list, ben, "WRITE");
        push(bensDevice, TODO, bike, Map.of("assignees", List.of(carl.memberId().toString())));
        annasDevice.push(SyncClient.deletion(TODO, bike, version("todo", bike)));

        rest.post()
                .uri("/api/v1/trash/" + TODO + "/" + bike + "/restore")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of())
                .exchange()
                .expectStatus()
                .is2xxSuccessful();

        assertThat(deletedAt("todo", bike)).isNull();
        assertThat(level(carl, TODO, bike)).isNull();
    }

    @Test
    void theOwnersAssignmentSharesWhomItAddsOnly() {
        UUID list = create(annasDevice, LIST, Map.of("name", "Presents"));
        UUID task = createIn(annasDevice, TODO, Map.of("title", "Wrap presents", "status", "OPEN"), LIST, list);
        share(anna, LIST, list, ben, "WRITE");
        var dana = invite("Dana", "dana");
        push(bensDevice, TODO, task, Map.of("assignees", List.of(carl.memberId().toString())));

        // Anna's app sends the whole list: Carl, whom Ben assigned, and Dana, whom she adds.
        push(annasDevice, TODO, task, Map.of(
                "assignees", List.of(carl.memberId().toString(), dana.memberId().toString())));

        assertThat(level(dana, TODO, task)).isEqualTo("CHECK");
        assertThat(level(carl, TODO, task)).isNull();

        // Taking Dana off and putting her back keeps her the owner's choice.
        push(annasDevice, TODO, task, Map.of("assignees", List.of(carl.memberId().toString())));
        assertThat(level(dana, TODO, task)).isNull();
        push(annasDevice, TODO, task, Map.of(
                "assignees", List.of(carl.memberId().toString(), dana.memberId().toString())));
        push(annasDevice, TODO, task, Map.of("status", "DONE"));
        assertThat(level(dana, TODO, task)).isEqualTo("CHECK");
    }

    // ---------------------------------------------------------------------------------
    // A resent mutation gets the answer it got the first time
    // ---------------------------------------------------------------------------------

    @Test
    void aResentRejectionIsRejectedAgainWithItsCode() {
        UUID list = create(annasDevice, LIST, Map.of("name", "Household"));
        share(anna, LIST, list, ben, "READ");
        var rename = SyncClient.mutation(LIST, list, version("todo_list", list), Map.of("name", "Bens"));

        var first = bensDevice.push(rename);
        // "Try again" on the app sends the same entry again, under the same mutation id.
        var again = bensDevice.push(rename);

        assertThat(first.getFirst().get("status")).isEqualTo("rejected");
        assertThat(again.getFirst().get("status")).isEqualTo("rejected");
        assertThat(again.getFirst().get("code")).isEqualTo(first.getFirst().get("code"));
        assertThat(db.fetchValue("select name from todo_list where id = ?", list)).isEqualTo("Household");
    }

    @Test
    void aResentConflictIsAConflictAgainWithTheServersValue() {
        UUID list = create(annasDevice, LIST, Map.of("name", "Household"));
        share(anna, LIST, list, ben, "WRITE");
        long base = version("todo_list", list);
        push(annasDevice, LIST, list, Map.of("name", "Home"));
        var stale = SyncClient.mutation(LIST, list, base, Map.of("name", "Bens"));

        var first = bensDevice.push(stale);
        var again = bensDevice.push(stale);

        assertThat(first.getFirst().get("status")).isEqualTo("conflict");
        assertThat(again.getFirst().get("status")).isEqualTo("conflict");
        assertThat((List<String>) again.getFirst().get("conflictFields")).containsExactly("name");
        assertThat((Map<String, Object>) again.getFirst().get("serverFields")).containsEntry("name", "Home");
    }

    @Test
    void aResentAppliedMutationIsStillADuplicate() {
        UUID list = create(annasDevice, LIST, Map.of("name", "Household"));
        var rename = SyncClient.mutation(LIST, list, version("todo_list", list), Map.of("name", "Home"));

        annasDevice.push(rename);
        var again = annasDevice.push(rename);

        assertThat(again.getFirst().get("status")).isEqualTo("duplicate");
    }

    // ---------------------------------------------------------------------------------
    // A subscription only in one's own calendar, and none for a disabled member
    // ---------------------------------------------------------------------------------

    @Test
    void aWriterCannotAttachASubscriptionToSomeoneElsesCalendar() {
        UUID family = create(annasDevice, CALENDAR, Map.of("name", "Family", "colorToken", "BLUE", "kind", "LOCAL"));
        share(anna, CALENDAR, family, ben, "WRITE");

        var result = bensDevice.push(SyncClient.withContainer(
                SyncClient.mutation("CALENDAR_SUBSCRIPTION", UUID.randomUUID(), null, subscription("Bens feed")),
                CALENDAR,
                family));

        assertThat(result.getFirst().get("status")).isEqualTo("rejected");
        assertThat(result.getFirst().get("code")).isEqualTo("access.denied");
        assertThat(db.fetchCount(db.selectFrom("calendar_subscription"))).isZero();
    }

    @Test
    void removingAStraySubscriptionLeavesTheCalendar() {
        UUID family = create(annasDevice, CALENDAR, Map.of("name", "Family", "colorToken", "BLUE", "kind", "LOCAL"));
        UUID dinner = createIn(annasDevice, EVENT, timed("Dinner"), CALENDAR, family);
        share(anna, CALENDAR, family, ben, "WRITE");
        // One attached before sync refused it.
        UUID stray = stray(family);

        var removed = annasDevice.push(
                SyncClient.deletion("CALENDAR_SUBSCRIPTION", stray, version("calendar_subscription", stray)));

        assertThat(removed.getFirst().get("status")).isEqualTo("applied");
        assertThat(deletedAt("calendar_subscription", stray)).isNotNull();
        assertThat(deletedAt("calendar", family)).isNull();
        assertThat(deletedAt("event", dinner)).isNull();
    }

    @Test
    void aStraySubscriptionNoLongerFillsSomeoneElsesCalendar() {
        UUID family = create(annasDevice, CALENDAR, Map.of("name", "Family", "colorToken", "BLUE", "kind", "LOCAL"));
        share(anna, CALENDAR, family, ben, "WRITE");
        UUID stray = stray(family);

        var result = refreshAsMember(anna, stray);

        assertThat(result.get("ok")).isEqualTo(false);
        assertThat(result.get("error")).isEqualTo("calendar.subscription_read_only");
    }

    @Test
    void aDisabledMembersSubscriptionStopsRefreshing() {
        UUID own = create(bensDevice, CALENDAR, Map.of("name", "Bens school", "colorToken", "BLUE", "kind", "EXTERNAL"));
        UUID subscription = createIn(bensDevice, "CALENDAR_SUBSCRIPTION", subscription("School"), CALENDAR, own);
        share(ben, CALENDAR, own, anna, "WRITE");
        rest.post()
                .uri("/api/v1/members/" + ben.memberId() + "/disable")
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .is2xxSuccessful();

        var result = refreshAsMember(anna, subscription);

        assertThat(result.get("ok")).isEqualTo(false);
        assertThat(result.get("error")).isEqualTo("calendar.subscription_read_only");
        assertThat(db.fetchValue("select last_error from calendar_subscription where id = ?", subscription))
                .isEqualTo("calendar.subscription_read_only");
    }

    /**
     * Ben's subscription in Anna's calendar, as sync took it before it was refused:
     * created as Anna, so its share is in place, then handed to Ben.
     */
    private UUID stray(UUID calendar) {
        UUID stray = createIn(annasDevice, "CALENDAR_SUBSCRIPTION", subscription("Bens feed"), CALENDAR, calendar);
        db.execute("update calendar_subscription set owner_id = ? where id = ?", ben.memberId(), stray);
        return stray;
    }

    private Map<String, Object> refreshAsMember(Family.Session who, UUID subscription) {
        return rest.post()
                .uri("/api/v1/calendar/subscriptions/" + subscription + "/refresh")
                .headers(who.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
    }

    private static Map<String, Object> subscription(String name) {
        return Map.of(
                "name", name, "url", "https://example.invalid/feed.ics", "targetKind", "EVENT",
                "syncInterval", "DAILY");
    }

    // ---------------------------------------------------------------------------------
    // The share sheet lists as assigned only whom the assignment shares with
    // ---------------------------------------------------------------------------------

    @Test
    void theSheetListsOnlyAssigneesTheAssignmentSharesWith() {
        UUID list = create(annasDevice, LIST, Map.of("name", "Household"));
        UUID task = createIn(annasDevice, TODO, Map.of("title", "Bins", "status", "OPEN"), LIST, list);
        var dana = invite("Dana", "dana");
        var emil = invite("Emil", "emil");
        putShares(anna, LIST, list, List.of(
                Map.of("subjectType", "MEMBER", "subjectId", ben.memberId().toString(), "level", "WRITE"),
                Map.of("subjectType", "MEMBER", "subjectId", dana.memberId().toString(), "level", "READ")));
        // Ben assigns Carl, who sees nothing, and Dana, who reads the list.
        push(bensDevice, TODO, task, Map.of(
                "assignees", List.of(carl.memberId().toString(), dana.memberId().toString())));
        // Anna adds Emil, who sees nothing yet.
        push(annasDevice, TODO, task, Map.of("assignees", List.of(
                carl.memberId().toString(), dana.memberId().toString(), emil.memberId().toString())));

        var sheet = rest.get()
                .uri("/api/v1/items/" + TODO + "/" + task + "/shares")
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        var assigned = ((List<Map<String, Object>>) sheet.get("entries")).stream()
                .filter(entry -> "ASSIGNED".equals(entry.get("source")))
                .map(entry -> entry.get("subjectId"))
                .toList();

        assertThat(assigned)
                .containsExactlyInAnyOrder(dana.memberId().toString(), emil.memberId().toString());
        assertThat(level(carl, TODO, task)).isNull();
    }

    // ---------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------

    /** A refresh of the subscription as the scheduler runs it, with a fixed file. */
    private void refresh(UUID subscription, UUID calendar) {
        Object subscriptions =
                org.springframework.test.util.AopTestUtils.getTargetObject(context.getBean("subscriptionService"));
        new org.springframework.transaction.support.TransactionTemplate(transactions)
                .executeWithoutResult(status -> org.springframework.test.util.ReflectionTestUtils.invokeMethod(
                        subscriptions, "apply", subscription, calendar, anna.memberId(), ics("Parents' evening")));
    }

    private static String ics(String summary) {
        return "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n"
                + "BEGIN:VEVENT\r\nUID:u1@example.org\r\nDTSTAMP:20260901T000000Z\r\n"
                + "DTSTART:20261013T170000Z\r\nDTEND:20261013T190000Z\r\nSUMMARY:" + summary + "\r\n"
                + "END:VEVENT\r\nEND:VCALENDAR\r\n";
    }

    private List<Map<String, Object>> push(SyncClient device, String type, UUID id, Map<String, Object> fields) {
        return device.push(SyncClient.mutation(type, id, version(table(type), id), fields));
    }

    private static String table(String type) {
        return switch (type) {
            case LIST -> "todo_list";
            case TODO -> "todo";
            case CALENDAR -> "calendar";
            case EVENT -> "event";
            default -> throw new IllegalArgumentException(type);
        };
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
}
