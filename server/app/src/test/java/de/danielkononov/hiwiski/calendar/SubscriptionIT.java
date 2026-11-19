package de.danielkononov.hiwiski.calendar;

import static de.danielkononov.hiwiski.db.generated.Tables.CALENDAR;
import static de.danielkononov.hiwiski.db.generated.Tables.CALENDAR_SUBSCRIPTION;
import static de.danielkononov.hiwiski.db.generated.Tables.EVENT;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import de.danielkononov.hiwiski.calendar.internal.SubscriptionTestAccess;
import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.FollowUps;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.util.Map;
import java.util.UUID;
import org.jooq.DSLContext;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * The ICS import.
 *
 * <p>Parts of the calendar's acceptance case: "a subscription with a broken file (the
 * subscription stays, the error is shown on it)" and "a deleted subscription takes its
 * calendar with it".
 */
@IntegrationTest
class SubscriptionIT {

    private static final String CALENDAR_TYPE = "CALENDAR";
    private static final String SUBSCRIPTION = "CALENDAR_SUBSCRIPTION";

    private static final String HOLIDAYS =
            """
            BEGIN:VCALENDAR\r
            VERSION:2.0\r
            PRODID:-//Land//Ferien//DE\r
            BEGIN:VEVENT\r
            UID:herbst-2026@land.de\r
            DTSTAMP:20260901T000000Z\r
            DTSTART;VALUE=DATE:20260929\r
            DTEND;VALUE=DATE:20261011\r
            SUMMARY:Herbstferien\r
            END:VEVENT\r
            BEGIN:VEVENT\r
            UID:elternabend-2026@schule.de\r
            DTSTAMP:20260901T000000Z\r
            DTSTART:20261013T170000Z\r
            DTEND:20261013T190000Z\r
            SUMMARY:Elternabend\r
            LOCATION:Aula\r
            END:VEVENT\r
            END:VCALENDAR\r
            """;

    @Autowired RestTestClient rest;

    @Autowired DSLContext db;

    @Autowired SubscriptionTestAccess.Access subscriptions;

    private record Sub(Family.Session session, SyncClient device, UUID calendarId, UUID subscriptionId) {}

    private Sub create() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);
        UUID calendarId = UUID.randomUUID();
        UUID subscriptionId = UUID.randomUUID();

        device.push(SyncClient.mutation(CALENDAR_TYPE, calendarId, null, Map.of(
                "name", "Schulferien", "kind", "EXTERNAL")));
        device.push(SyncClient.withContainer(
                SyncClient.mutation(SUBSCRIPTION, subscriptionId, null, Map.of(
                        "name", "Schulferien",
                        "url", "https://example.invalid/holidays.ics",
                        "targetKind", "EVENT",
                        "syncInterval", "DAILY")),
                CALENDAR_TYPE,
                calendarId));
        return new Sub(session, device, calendarId, subscriptionId);
    }

    /**
     * A new subscription is fetched right away -- not at the next run of the hourly job.
     * The source here does not resolve, so the attempt shows up as the error on it.
     */
    @Test
    void aNewSubscriptionIsFetchedRightAway() {
        var sub = create();

        FollowUps.await(db);

        var row = db.selectFrom(CALENDAR_SUBSCRIPTION)
                .where(CALENDAR_SUBSCRIPTION.ID.eq(sub.subscriptionId()))
                .fetchOne();
        assertThat(row.getLastError()).describedAs("fetched without anyone tapping refresh").isNotNull();
    }

    @Test
    void importsAndMatchesByUid() {
        var sub = create();

        int count = subscriptions.apply(sub.subscriptionId(), sub.calendarId(), sub.session().memberId(), HOLIDAYS);
        assertThat(count).isEqualTo(2);
        assertThat(db.fetchCount(EVENT)).isEqualTo(2);

        // All-day is a date, and DTEND is exclusive in the standard: the last day of the
        // holidays is the 10th, not the 11th.
        var holidays = db.selectFrom(EVENT).where(EVENT.SOURCE_UID.eq("herbst-2026@land.de")).fetchOne();
        assertThat(holidays.getTimeForm()).isEqualTo("ALL_DAY");
        assertThat(holidays.getStartDate()).isEqualTo(java.time.LocalDate.of(2026, 9, 29));
        assertThat(holidays.getEndDate()).isEqualTo(java.time.LocalDate.of(2026, 10, 10));
        // Imported events get NO readable key: a holiday calendar would use up five
        // hundred numbers for something nobody cites.
        assertThat(holidays.getEntityKey()).isNull();

        // The same sync once more creates no duplicates -- matching is by UID, never by
        // title.
        subscriptions.apply(sub.subscriptionId(), sub.calendarId(), sub.session().memberId(), HOLIDAYS);
        assertThat(db.fetchCount(EVENT)).isEqualTo(2);
    }

    /**
     * A calendar is written in batches, each in a transaction of its own: in one
     * transaction a large one held the writer lock for minutes, and no device could save
     * anything meanwhile. Batch by batch it still arrives whole, matches by UID on the
     * next run, and what has gone from the source goes in the last step.
     */
    @Test
    void aCalendarLargerThanOneBatchArrivesWhole() {
        var sub = create();
        int events = 450;
        var file = new StringBuilder("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n");
        for (int i = 0; i < events; i++) {
            file.append("BEGIN:VEVENT\r\nUID:termin-").append(i).append("@quelle.de\r\n")
                    .append("DTSTART:20261120T100000Z\r\nSUMMARY:Termin ").append(i).append("\r\nEND:VEVENT\r\n");
        }
        String all = file + "END:VCALENDAR\r\n";

        int count = subscriptions.apply(sub.subscriptionId(), sub.calendarId(), sub.session().memberId(), all);
        assertThat(count).isEqualTo(events);
        assertThat(db.fetchCount(EVENT, EVENT.DELETED_AT.isNull())).isEqualTo(events);

        subscriptions.apply(sub.subscriptionId(), sub.calendarId(), sub.session().memberId(), all);
        assertThat(db.fetchCount(EVENT)).isEqualTo(events);

        // The last one has gone from the source.
        String shorter = all.replace(
                "BEGIN:VEVENT\r\nUID:termin-" + (events - 1) + "@quelle.de\r\nDTSTART:20261120T100000Z\r\nSUMMARY:Termin "
                        + (events - 1) + "\r\nEND:VEVENT\r\n",
                "");
        subscriptions.apply(sub.subscriptionId(), sub.calendarId(), sub.session().memberId(), shorter);
        assertThat(db.fetchCount(EVENT, EVENT.DELETED_AT.isNull())).isEqualTo(events - 1);
    }

    @Test
    void aLocalAdditionSurvivesTheSync() {
        var sub = create();
        subscriptions.apply(sub.subscriptionId(), sub.calendarId(), sub.session().memberId(), HOLIDAYS);

        UUID eventId = db.select(EVENT.ID)
                .from(EVENT)
                .where(EVENT.SOURCE_UID.eq("elternabend-2026@schule.de"))
                .fetchOne(EVENT.ID);

        // The user sets a reminder.
        db.update(EVENT).set(EVENT.REMINDER_MINUTES, 60).where(EVENT.ID.eq(eventId)).execute();

        // The source changes the title.
        String changed = HOLIDAYS.replace("SUMMARY:Elternabend", "SUMMARY:Elternabend (verschoben)");
        subscriptions.apply(sub.subscriptionId(), sub.calendarId(), sub.session().memberId(), changed);

        var event = db.selectFrom(EVENT).where(EVENT.ID.eq(eventId)).fetchOne();
        // Title and time belong to the source...
        assertThat(event.getTitle()).isEqualTo("Elternabend (verschoben)");
        // ...reminder and assignment to the user.
        assertThat(event.getReminderMinutes()).isEqualTo(60);
    }

    @Test
    void whatDisappearsFromTheSourceDisappearsHereToo() {
        var sub = create();
        subscriptions.apply(sub.subscriptionId(), sub.calendarId(), sub.session().memberId(), HOLIDAYS);

        String onlyOne = HOLIDAYS.replaceAll("(?s)BEGIN:VEVENT\r\nUID:elternabend.*?END:VEVENT\r\n", "");
        subscriptions.apply(sub.subscriptionId(), sub.calendarId(), sub.session().memberId(), onlyOne);

        assertThat(db.fetchCount(EVENT, EVENT.DELETED_AT.isNull())).isEqualTo(1);
    }

    /**
     * An event the source still has but that cannot be read is not gone. Deleting it
     * took what the user had added to it.
     */
    @Test
    void anUnreadableEventIsNotDeleted() {
        var sub = create();
        subscriptions.apply(sub.subscriptionId(), sub.calendarId(), sub.session().memberId(), HOLIDAYS);

        String broken = HOLIDAYS.replace(
                "DTSTART:20261013T170000Z", "DTSTART;TZID=/vendor/Nowhere/Land:20261013T170000");
        subscriptions.apply(sub.subscriptionId(), sub.calendarId(), sub.session().memberId(), broken);

        assertThat(db.fetchCount(EVENT, EVENT.DELETED_AT.isNull())).isEqualTo(2);
    }

    /**
     * The scheduled run and "sync now" at once: both looked for the UID first and
     * inserted after, and the event was there twice -- every refresh after failed.
     */
    @Test
    void twoImportsAtOnceWriteEachEventOnce() throws Exception {
        var sub = create();
        var start = new java.util.concurrent.CountDownLatch(1);
        var pool = java.util.concurrent.Executors.newFixedThreadPool(2);
        try {
            var runs = java.util.stream.IntStream.range(0, 2)
                    .mapToObj(i -> pool.submit(() -> {
                        start.await();
                        return subscriptions.apply(
                                sub.subscriptionId(), sub.calendarId(), sub.session().memberId(), HOLIDAYS);
                    }))
                    .toList();
            start.countDown();
            for (var run : runs) {
                assertThat(run.get()).isEqualTo(2);
            }
        } finally {
            pool.shutdown();
        }

        assertThat(db.fetchCount(EVENT, EVENT.CALENDAR_ID.eq(sub.calendarId()))).isEqualTo(2);
    }

    /** A source that briefly answers with an empty calendar does not wipe ours. */
    @Test
    void anEmptyFileDeletesNothing() {
        var sub = create();
        subscriptions.apply(sub.subscriptionId(), sub.calendarId(), sub.session().memberId(), HOLIDAYS);

        String empty = HOLIDAYS.replaceAll("(?s)BEGIN:VEVENT.*END:VEVENT\r\n", "");
        subscriptions.apply(sub.subscriptionId(), sub.calendarId(), sub.session().memberId(), empty);

        assertThat(db.fetchCount(EVENT, EVENT.DELETED_AT.isNull())).isEqualTo(2);
    }

    @SuppressWarnings("unchecked")
    private java.util.List<Object> hits(Sub sub, String query) {
        FollowUps.await(db);
        var body = rest.get()
                .uri("/api/v1/search?q={q}", query)
                .headers(sub.session().auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        return (java.util.List<Object>) body.get("hits");
    }

    /** What the import writes is found -- and what the source removed is not any more. */
    @Test
    void importedEventsAreSearchable() {
        var sub = create();
        subscriptions.apply(sub.subscriptionId(), sub.calendarId(), sub.session().memberId(), HOLIDAYS);
        assertThat(hits(sub, "Elternabend")).hasSize(1);

        String onlyOne = HOLIDAYS.replaceAll("(?s)BEGIN:VEVENT\r\nUID:elternabend.*?END:VEVENT\r\n", "");
        subscriptions.apply(sub.subscriptionId(), sub.calendarId(), sub.session().memberId(), onlyOne);
        assertThat(hits(sub, "Elternabend")).isEmpty();
    }

    @Test
    void aBrokenFileKeepsTheSubscriptionAndRecordsTheError() {
        var sub = create();

        // Recording the error needs its OWN transaction. In an earlier version the catch ran in the
        // same, aborted one -- instead of a readable state on the subscription the user got
        // a server error, and the subscription was never even created.
        assertThatThrownBy(() -> subscriptions.refresh(sub.subscriptionId()))
                .isInstanceOf(RuntimeException.class);

        var subscription = db.selectFrom(CALENDAR_SUBSCRIPTION)
                .where(CALENDAR_SUBSCRIPTION.ID.eq(sub.subscriptionId()))
                .fetchOne();
        assertThat(subscription).describedAs("the subscription stays").isNotNull();
        assertThat(subscription.getLastError()).describedAs("and the error is recorded on it").isNotNull();

        // **And the device learns about it.** When clicking through, the subscription still
        // said "Not synced yet" although the server had long had the error in the column:
        // the note was written as a direct UPDATE, and the pull only reads the log.
        // A direct UPDATE on a synced item is always a bug -- even when it is
        // "just" a status field.
        sub.device().setLastSeq(0);
        var entries = sub.device().pullAll();
        assertThat(entries)
                .describedAs("the error note reaches the device as a log entry")
                .anySatisfy(entry -> {
                    assertThat(entry.get("entityType")).isEqualTo(SUBSCRIPTION);
                    @SuppressWarnings("unchecked")
                    var fields = (java.util.Map<String, Object>) entry.get("fields");
                    assertThat(fields).containsKey("lastError");
                    assertThat(fields.get("lastError")).isNotNull();
                });
    }

    @Test
    void aDeletedSubscriptionTakesItsCalendarWithIt() {
        var sub = create();
        subscriptions.apply(sub.subscriptionId(), sub.calendarId(), sub.session().memberId(), HOLIDAYS);

        long version = db.select(CALENDAR_SUBSCRIPTION.VERSION)
                .from(CALENDAR_SUBSCRIPTION)
                .where(CALENDAR_SUBSCRIPTION.ID.eq(sub.subscriptionId()))
                .fetchOne(CALENDAR_SUBSCRIPTION.VERSION);

        sub.device().push(SyncClient.deletion(SUBSCRIPTION, sub.subscriptionId(), version));

        // In an earlier version the calendar stayed: afterwards it sat empty in the picker for a new
        // event and accepted nothing there, because it was external.
        assertThat(db.fetchCount(CALENDAR, CALENDAR.DELETED_AT.isNull())).isZero();
        // And its events go too -- otherwise they would still be there on the devices.
        assertThat(db.fetchCount(EVENT, EVENT.DELETED_AT.isNull())).isZero();
    }

    private org.springframework.test.web.servlet.client.RestTestClient.ResponseSpec importInto(
            Family.Session session, UUID calendarId, String ics) {
        return rest.post()
                .uri("/api/v1/calendars/" + calendarId + "/import")
                .headers(session.auth())
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                .body(Map.of("ics", ics))
                .exchange();
    }

    /** A file into one's own calendar: ordinary events, and a second import doubles nothing. */
    @Test
    void anIcsFileImportsIntoOnesOwnCalendarAndASecondImportUpdates() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);
        UUID calendarId = UUID.randomUUID();
        device.push(SyncClient.mutation(CALENDAR_TYPE, calendarId, null, Map.of("name", "Family")));

        importInto(session, calendarId, HOLIDAYS)
                .expectStatus().isOk()
                .expectBody()
                .jsonPath("$.importedCount").isEqualTo(2)
                .jsonPath("$.updatedCount").isEqualTo(0);
        importInto(session, calendarId, HOLIDAYS)
                .expectStatus().isOk()
                .expectBody()
                .jsonPath("$.importedCount").isEqualTo(0)
                .jsonPath("$.updatedCount").isEqualTo(2);

        assertThat(db.fetchCount(EVENT, EVENT.CALENDAR_ID.eq(calendarId))).isEqualTo(2);
    }

    @Test
    void aSubscribedCalendarTakesNoImport() {
        var sub = create();

        importInto(sub.session(), sub.calendarId(), HOLIDAYS)
                .expectStatus().isBadRequest()
                .expectBody()
                .jsonPath("$.code").isEqualTo("calendar.import_into_subscription");
    }

    @Test
    void thePreviewOfAnUnreachableAddressSaysSo() {
        var session = Family.setUp(rest);

        rest.post()
                .uri("/api/v1/calendar/subscriptions/preview")
                .headers(session.auth())
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                .body(Map.of("url", "https://example.invalid/holidays.ics"))
                .exchange()
                .expectStatus().isBadRequest()
                .expectBody()
                .jsonPath("$.code").isEqualTo("net.host_unknown");
    }

    /** A file into a calendar the import creates — locked, it is ours but read only. */
    @Test
    void anImportCanCreateALockedCalendar() {
        var session = Family.setUp(rest);
        UUID calendarId = UUID.randomUUID();

        rest.post()
                .uri("/api/v1/calendars/" + calendarId + "/import")
                .headers(session.auth())
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "ics", HOLIDAYS,
                        "newCalendar", Map.of("name", "Schule", "colorToken", "TEAL", "locked", true)))
                .exchange()
                .expectStatus().isOk()
                .expectBody()
                .jsonPath("$.importedCount").isEqualTo(2);

        var calendar = db.selectFrom(CALENDAR).where(CALENDAR.ID.eq(calendarId)).fetchOne();
        assertThat(calendar).isNotNull();
        assertThat(calendar.getName()).isEqualTo("Schule");
        assertThat(calendar.getKind()).isEqualTo("IMPORTED");
        assertThat(calendar.getOwnerId()).isEqualTo(session.memberId());
        assertThat(db.fetchCount(EVENT, EVENT.CALENDAR_ID.eq(calendarId))).isEqualTo(2);

        // A second import updates the locked calendar -- that is its only way in.
        importInto(session, calendarId, HOLIDAYS)
                .expectStatus().isOk()
                .expectBody()
                .jsonPath("$.updatedCount").isEqualTo(2);
    }

    @Test
    void thePreviewReadsAFileSentAlong() {
        var session = Family.setUp(rest);

        rest.post()
                .uri("/api/v1/calendar/subscriptions/preview")
                .headers(session.auth())
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                .body(Map.of("ics", HOLIDAYS))
                .exchange()
                .expectStatus().isOk()
                .expectBody()
                .jsonPath("$.eventCount").isEqualTo(2);
    }

    @Test
    void anImportWithoutFileOrAddressSaysSo() {
        var session = Family.setUp(rest);

        rest.post()
                .uri("/api/v1/calendars/" + UUID.randomUUID() + "/import")
                .headers(session.auth())
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                .body(Map.of())
                .exchange()
                .expectStatus().isBadRequest()
                .expectBody()
                .jsonPath("$.code").isEqualTo("calendar.import_source_missing");
    }
}
