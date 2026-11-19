package de.danielkononov.hiwiski.calendar.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.CALENDAR_SUBSCRIPTION;
import static de.danielkononov.hiwiski.db.generated.Tables.EVENT;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.FollowUps;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.util.Map;
import java.util.UUID;
import org.jooq.DSLContext;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * The first fetch of a new subscription when the source <em>does</em> deliver.
 *
 * <p>SubscriptionIT only covers the unreachable source: nothing is written, so nothing is
 * locked. With events to write, the first fetch used to run inside the listener's
 * transaction, held the row lock on the change sequence and then waited for
 * {@code recordSuccess} in a transaction of its own — which waited for that lock. The
 * server stood still until a restart, and every other write with it.
 */
@IntegrationTest
class SubscriptionFirstFetchIT {

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
            END:VCALENDAR\r
            """;

    @Autowired RestTestClient rest;

    @Autowired DSLContext db;

    @MockitoBean IcsFetcher fetcher;

    @Test
    void aNewSubscriptionWithEventsIsFetchedAndTheServerKeepsWriting() {
        when(fetcher.fetch(anyString())).thenReturn(HOLIDAYS);
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);
        UUID calendarId = UUID.randomUUID();
        UUID subscriptionId = UUID.randomUUID();

        device.push(SyncClient.mutation("CALENDAR", calendarId, null, Map.of(
                "name", "Schulferien", "kind", "EXTERNAL")));
        device.push(SyncClient.withContainer(
                SyncClient.mutation("CALENDAR_SUBSCRIPTION", subscriptionId, null, Map.of(
                        "name", "Schulferien",
                        "url", "https://example.invalid/holidays.ics",
                        "targetKind", "EVENT",
                        "syncInterval", "DAILY")),
                "CALENDAR",
                calendarId));

        FollowUps.await(db);

        var row = db.selectFrom(CALENDAR_SUBSCRIPTION)
                .where(CALENDAR_SUBSCRIPTION.ID.eq(subscriptionId))
                .fetchOne();
        assertThat(row.getLastSyncAt()).describedAs("the success is noted").isNotNull();
        assertThat(row.getImportedCount()).isEqualTo(1);
        assertThat(db.fetchCount(EVENT, EVENT.CALENDAR_ID.eq(calendarId))).isEqualTo(1);

        // And the next write goes through instead of queueing behind a lock.
        device.push(SyncClient.mutation("CALENDAR", UUID.randomUUID(), null, Map.of(
                "name", "Arzttermine", "kind", "LOCAL")));
    }
}
