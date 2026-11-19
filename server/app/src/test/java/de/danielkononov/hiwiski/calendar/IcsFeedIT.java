package de.danielkononov.hiwiski.calendar;

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
 * The ICS export.
 *
 * <p>Part of the calendar's acceptance case: "an export in a third-party calendar app". This
 * tests what a third-party app sees — without signing in, read-only, and with the series
 * as an `RRULE` instead of expanded.
 */
@IntegrationTest
class IcsFeedIT {

    private static final String CALENDAR = "CALENDAR";
    private static final String EVENT = "EVENT";
    private static final String FEED = "CALENDAR_FEED";

    @Autowired RestTestClient rest;

    @Autowired de.danielkononov.hiwiski.calendar.internal.IcsImporterTestAccess.Reader reader;

    private String ics(String token) {
        return rest.get()
                .uri("/ics/" + token + ".ics")
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(String.class)
                .returnResult()
                .getResponseBody();
    }

    @Test
    void aThirdPartyAppGetsAValidFile() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);

        UUID calendarId = UUID.randomUUID();
        device.push(SyncClient.mutation(CALENDAR, calendarId, null, Map.of("name", "Familie")));
        device.push(SyncClient.withContainer(
                SyncClient.mutation(EVENT, UUID.randomUUID(), null, Map.of(
                        "title", "Elternabend; mit Komma, und Semikolon",
                        "timeForm", "TIMED",
                        "startsAt", "2026-10-13T19:00:00Z",
                        "endsAt", "2026-10-13T21:00:00Z",
                        "location", "Schule")),
                CALENDAR,
                calendarId));
        device.push(SyncClient.withContainer(
                SyncClient.mutation(EVENT, UUID.randomUUID(), null, Map.of(
                        "title", "Müll rausstellen",
                        "timeForm", "RECURRING",
                        "localStart", "2026-10-05T08:00:00",
                        "timeZone", "Europe/Berlin",
                        "rrule", "FREQ=WEEKLY;BYDAY=MO")),
                CALENDAR,
                calendarId));

        String token = "probe-" + UUID.randomUUID();
        device.push(SyncClient.mutation(FEED, UUID.randomUUID(), null, Map.of(
                "name", "Familie Berger",
                "calendarIds", List.of(calendarId.toString()),
                "contentMode", "FULL",
                "token", token)));

        String file = ics(token);

        assertThat(file).startsWith("BEGIN:VCALENDAR\r\n");
        assertThat(file).endsWith("END:VCALENDAR\r\n");
        assertThat(file).contains("X-WR-CALNAME:Familie Berger");
        // Semicolon and comma must be escaped, otherwise a third-party app reads a new
        // parameter after them.
        assertThat(file).contains("SUMMARY:Elternabend\\; mit Komma\\, und Semikolon");
        assertThat(file).contains("LOCATION:Schule");
        assertThat(file).contains("DTSTART:20261013T190000Z");
        // Series go out as an RRULE, NOT expanded -- every client handles that, and it
        // keeps the file small.
        assertThat(file).contains("RRULE:FREQ=WEEKLY;BYDAY=MO");
        // With zone and local time: in UTC the series would shift when daylight saving
        // time changes.
        assertThat(file).contains("DTSTART;TZID=Europe/Berlin:20261005T080000");
    }

    /**
     * The acceptance case "an export in a third-party calendar app".
     *
     * <p>It is tested as far as a machine can: our own hand-written file is read by a
     * <strong>third-party</strong> library. Testing the writer only against our own writer
     * tests nothing — and exactly the edge cases where third-party apps fail (line folding,
     * escaping, zone information) would then only surface at the user's end.
     */
    @Test
    void ourOwnFileCanBeReadByAThirdPartyLibrary() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);

        UUID calendarId = UUID.randomUUID();
        device.push(SyncClient.mutation(CALENDAR, calendarId, null, Map.of("name", "Familie")));
        device.push(SyncClient.withContainer(
                SyncClient.mutation(EVENT, UUID.randomUUID(), null, Map.of(
                        "title", "Elternabend; mit Komma, und einem sehr langen Titel, "
                                + "damit die Zeile umgebrochen werden muss und ein fremdes "
                                + "Programm die Fortsetzung wieder zusammensetzt",
                        "timeForm", "TIMED",
                        "startsAt", "2026-10-13T19:00:00Z",
                        "endsAt", "2026-10-13T21:00:00Z")),
                CALENDAR,
                calendarId));
        device.push(SyncClient.withContainer(
                SyncClient.mutation(EVENT, UUID.randomUUID(), null, Map.of(
                        "title", "Müll rausstellen",
                        "timeForm", "RECURRING",
                        // **Without seconds and with prefix** -- exactly the way the UI
                        // writes it. In the acceptance case "an export in a third-party
                        // calendar app" both ended up wrong in the file:
                        // `DTSTART;TZID=Europe/Berlin:20261005T0800` without seconds and
                        // `RRULE:RRULE:FREQ=WEEKLY`. The test had not found them because it
                        // produced its own data more cleanly than the app.
                        "localStart", "2026-10-05T08:00",
                        "localEnd", "2026-10-05T08:15",
                        "timeZone", "Europe/Berlin",
                        "rrule", "RRULE:FREQ=WEEKLY;BYDAY=MO")),
                CALENDAR,
                calendarId));
        device.push(SyncClient.withContainer(
                SyncClient.mutation(EVENT, UUID.randomUUID(), null, Map.of(
                        "title", "Sommerferien",
                        "timeForm", "ALL_DAY",
                        "startDate", "2026-07-16",
                        "endDate", "2026-08-26")),
                CALENDAR,
                calendarId));

        String token = "probe-" + UUID.randomUUID();
        device.push(SyncClient.mutation(FEED, UUID.randomUUID(), null, Map.of(
                "name", "Familie",
                "calendarIds", List.of(calendarId.toString()),
                "contentMode", "FULL",
                "token", token)));

        String file = ics(token);

        assertThat(reader.count(file)).isEqualTo(3);
        // The folded title comes back out unfolded.
        assertThat(reader.titles(file))
                .anySatisfy(title -> assertThat(title)
                        .startsWith("Elternabend; mit Komma, und einem sehr langen Titel")
                        .endsWith("wieder zusammensetzt"));
        assertThat(reader.titles(file)).contains("Müll rausstellen", "Sommerferien");

        // The prefix appears exactly once, and the timestamp has seconds.
        assertThat(file).contains("RRULE:FREQ=WEEKLY;BYDAY=MO");
        assertThat(file).doesNotContain("RRULE:RRULE:");
        assertThat(file).contains("DTSTART;TZID=Europe/Berlin:20261005T080000");
        assertThat(file).contains("DTEND;TZID=Europe/Berlin:20261005T081500");
        // And the third-party library really reads the series as a series.
        assertThat(reader.rrules(file)).contains("FREQ=WEEKLY;BYDAY=MO");
    }

    @Test
    void aCancelledOccurrenceGoesOutAsExdate() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);

        UUID calendarId = UUID.randomUUID();
        UUID eventId = UUID.randomUUID();
        device.push(SyncClient.mutation(CALENDAR, calendarId, null, Map.of("name", "Familie")));
        device.push(SyncClient.withContainer(
                SyncClient.mutation(EVENT, eventId, null, Map.of(
                        "title", "Müll rausstellen",
                        "timeForm", "RECURRING",
                        "localStart", "2026-10-05T08:00:00",
                        "timeZone", "Europe/Berlin",
                        "rrule", "FREQ=WEEKLY;BYDAY=MO")),
                CALENDAR,
                calendarId));
        // Cancel a single occurrence -- the key is the ORIGINAL start.
        device.push(SyncClient.withContainer(
                SyncClient.mutation(EVENT, eventId, 1L, Map.of(
                        "exceptions", Map.of("2026-10-12T08:00", Map.of("cancelled", true)))),
                CALENDAR,
                calendarId));

        String token = "probe-" + UUID.randomUUID();
        device.push(SyncClient.mutation(FEED, UUID.randomUUID(), null, Map.of(
                "name", "Familie",
                "calendarIds", List.of(calendarId.toString()),
                "contentMode", "FULL",
                "token", token)));

        String file = ics(token);

        // Without EXDATE the third-party app would show an event that no longer exists
        // here -- and that is exactly how you notice an export that is only almost right.
        assertThat(file).contains("RRULE:FREQ=WEEKLY;BYDAY=MO");
        assertThat(file).contains("EXDATE;TZID=Europe/Berlin:20261012T0800");
    }

    @Test
    void busyOnlyRevealsNoTitles() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);

        UUID calendarId = UUID.randomUUID();
        device.push(SyncClient.mutation(CALENDAR, calendarId, null, Map.of("name", "Arbeit")));
        device.push(SyncClient.withContainer(
                SyncClient.mutation(EVENT, UUID.randomUUID(), null, Map.of(
                        "title", "Kündigungsgespräch",
                        "timeForm", "TIMED",
                        "startsAt", "2026-10-13T09:00:00Z",
                        "location", "Büro")),
                CALENDAR,
                calendarId));

        String token = "busy-" + UUID.randomUUID();
        device.push(SyncClient.mutation(FEED, UUID.randomUUID(), null, Map.of(
                "name", "Für Oma",
                "calendarIds", List.of(calendarId.toString()),
                "contentMode", "BUSY",
                "token", token)));

        String file = ics(token);

        // "Grandma should see that something is on" -- not what.
        assertThat(file).doesNotContain("Kündigungsgespräch");
        assertThat(file).doesNotContain("Büro");
        assertThat(file).contains("SUMMARY:Busy");
        assertThat(file).contains("DTSTART:20261013T090000Z");
    }

    @Test
    void aRevokedLinkLooksLikeAMadeUpOne() {
        Family.setUp(rest);
        rest.get().uri("/ics/does-not-exist.ics").exchange().expectStatus().isNotFound();
    }

    @Test
    void longLinesAreFolded() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);

        UUID calendarId = UUID.randomUUID();
        device.push(SyncClient.mutation(CALENDAR, calendarId, null, Map.of("name", "Lang")));
        String longTitle = "Ü".repeat(200);
        device.push(SyncClient.withContainer(
                SyncClient.mutation(EVENT, UUID.randomUUID(), null, Map.of(
                        "title", longTitle,
                        "timeForm", "TIMED",
                        "startsAt", "2026-10-13T09:00:00Z")),
                CALENDAR,
                calendarId));

        String token = "lang-" + UUID.randomUUID();
        device.push(SyncClient.mutation(FEED, UUID.randomUUID(), null, Map.of(
                "name", "Lang",
                "calendarIds", List.of(calendarId.toString()),
                "token", token)));

        // RFC 5545 requires at most 75 octets per line; otherwise some apps choke on a long
        // title -- a bug that only shows up with long titles.
        for (String line : ics(token).split("\r\n")) {
            assertThat(line.getBytes(java.nio.charset.StandardCharsets.UTF_8).length)
                    .describedAs("line: %s", line)
                    .isLessThanOrEqualTo(75);
        }
    }
}
