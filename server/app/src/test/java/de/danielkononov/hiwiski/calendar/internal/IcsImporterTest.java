package de.danielkononov.hiwiski.calendar.internal;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.recurrence.internal.RecurrenceTestAccess;
import java.time.LocalDate;
import java.util.Map;
import org.junit.jupiter.api.Test;

/** What a foreign file becomes: every series in a form the app expands. */
class IcsImporterTest {

    private final IcsImporter importer = new IcsImporter(RecurrenceTestAccess.create());

    private static String calendar(String... event) {
        return "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//EN\r\nBEGIN:VEVENT\r\n"
                + String.join("\r\n", event)
                + "\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";
    }

    // Rules from a feed were stored unchecked.
    @org.junit.jupiter.params.ParameterizedTest
    @org.junit.jupiter.params.provider.ValueSource(strings = {
        "FREQ=SECONDLY;BYMONTH=2;BYMONTHDAY=29",
        "FREQ=MINUTELY;BYSETPOS=2;BYMINUTE=0",
        "FREQ=HOURLY;BYWEEKNO=53;BYMONTH=6",
        "FREQ=HOURLY;BYYEARDAY=366;BYMONTH=1",
    })
    void aRuleThatCannotBeStoredMakesASingleEvent(String rule) {
        var parsed = importer.read(calendar(
                "UID:r1", "SUMMARY:Lesson", "DTSTART:20260105T080000Z", "DTEND:20260105T083000Z", "RRULE:" + rule,
                "END:VEVENT", "BEGIN:VEVENT",
                "UID:r2", "SUMMARY:Choir", "DTSTART;VALUE=DATE:20260106", "RRULE:" + rule));

        assertThat(parsed.unreadable()).isEmpty();
        assertThat(parsed.entries()).hasSize(2).allSatisfy(entry -> assertThat(entry.rrule()).isNull());
        assertThat(parsed.entries().getFirst().timeForm()).isEqualTo("TIMED");
        assertThat(parsed.entries().get(1).timeForm()).isEqualTo("ALL_DAY");
    }

    @Test
    void aYearlyBirthdayIsASeriesOfWholeDays() {
        var entry = importer.parse(calendar(
                        "UID:b1", "SUMMARY:Anna", "DTSTART;VALUE=DATE:20200101", "RRULE:FREQ=YEARLY"))
                .getFirst();

        assertThat(entry.timeForm()).isEqualTo("ALL_DAY");
        assertThat(entry.startDate()).isEqualTo(LocalDate.of(2020, 1, 1));
        assertThat(entry.rrule()).isEqualTo("FREQ=YEARLY");
    }

    @Test
    void aUtcSeriesRepeatsInUtc() {
        var entry = importer.parse(calendar(
                        "UID:w1",
                        "SUMMARY:Standup",
                        "DTSTART:20260105T080000Z",
                        "DTEND:20260105T083000Z",
                        "RRULE:FREQ=WEEKLY"))
                .getFirst();

        assertThat(entry.timeForm()).isEqualTo("RECURRING");
        assertThat(entry.localStart()).isEqualTo("2026-01-05T08:00");
        assertThat(entry.localEnd()).isEqualTo("2026-01-05T08:30");
        assertThat(entry.timeZone()).isEqualTo("UTC");
    }

    @Test
    void aFloatingSeriesIsASeriesToo() {
        var entry = importer.parse(calendar(
                        "UID:f1", "SUMMARY:Choir", "DTSTART:20260105T190000", "RRULE:FREQ=WEEKLY"))
                .getFirst();

        assertThat(entry.timeForm()).isEqualTo("RECURRING");
        assertThat(entry.localStart()).isEqualTo("2026-01-05T19:00");
    }

    @Test
    void anExcludedDayIsCancelled() {
        var entry = importer.parse(calendar(
                        "UID:s1",
                        "SUMMARY:Lesson",
                        "DTSTART;TZID=Europe/Berlin:20261005T080000",
                        "RRULE:FREQ=WEEKLY",
                        "EXDATE;TZID=Europe/Berlin:20261012T080000"))
                .getFirst();

        assertThat(entry.exceptions()).containsEntry("2026-10-12T08:00", Map.of("cancelled", true));
    }

    @Test
    void anOverrideIsAMoveOfItsSeriesNotAnEventOfItsOwn() {
        String ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//EN\r\n"
                + "BEGIN:VEVENT\r\nUID:s1\r\nSUMMARY:Lesson\r\n"
                + "DTSTART;TZID=Europe/Berlin:20261005T080000\r\n"
                + "DTEND;TZID=Europe/Berlin:20261005T090000\r\nRRULE:FREQ=WEEKLY\r\nEND:VEVENT\r\n"
                + "BEGIN:VEVENT\r\nUID:s1\r\nSUMMARY:Lesson\r\n"
                + "RECURRENCE-ID;TZID=Europe/Berlin:20261012T080000\r\n"
                + "DTSTART;TZID=Europe/Berlin:20261012T100000\r\n"
                + "DTEND;TZID=Europe/Berlin:20261012T110000\r\nEND:VEVENT\r\n"
                + "END:VCALENDAR\r\n";

        var entries = importer.parse(ics);

        assertThat(entries).hasSize(1);
        assertThat(entries.getFirst().exceptions())
                .containsEntry("2026-10-12T08:00", Map.of("start", "2026-10-12T10:00", "end", "2026-10-12T11:00"));
    }

    @Test
    void anAllDaySeriesExcludesDays() {
        var entry = importer.parse(calendar(
                        "UID:b1",
                        "SUMMARY:Anna",
                        "DTSTART;VALUE=DATE:20200314",
                        "RRULE:FREQ=YEARLY",
                        "EXDATE;VALUE=DATE:20260314"))
                .getFirst();

        assertThat(entry.exceptions()).containsEntry("2026-03-14T00:00", Map.of("cancelled", true));
    }

    @Test
    void anOutlookZoneIsTheIanaOne() {
        var entry = importer.parse(calendar(
                        "UID:o1",
                        "SUMMARY:Team",
                        "DTSTART;TZID=W. Europe Standard Time:20260105T080000",
                        "RRULE:FREQ=WEEKLY",
                        "EXDATE;TZID=W. Europe Standard Time:20260112T080000"))
                .getFirst();

        assertThat(entry.timeZone()).isEqualTo("Europe/Berlin");
        assertThat(entry.localStart()).isEqualTo("2026-01-05T08:00");
        assertThat(entry.exceptions()).containsKey("2026-01-12T08:00");
    }

    @Test
    void aThunderbirdZoneIsTheIanaOne() {
        var entry = importer.parse(calendar(
                        "UID:m1",
                        "SUMMARY:Choir",
                        "DTSTART;TZID=/mozilla.org/20050126_1/America/New_York:20260105T190000",
                        "RRULE:FREQ=WEEKLY"))
                .getFirst();

        assertThat(entry.timeZone()).isEqualTo("America/New_York");
        assertThat(entry.localStart()).isEqualTo("2026-01-05T19:00");
    }

    @Test
    void anUnknownZoneWithItsDefinitionKeepsTheInstant() {
        String ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//EN\r\n"
                + "BEGIN:VTIMEZONE\r\nTZID:Customized Time Zone\r\n"
                + "BEGIN:STANDARD\r\nDTSTART:16010101T000000\r\nTZOFFSETFROM:+0100\r\nTZOFFSETTO:+0100\r\n"
                + "END:STANDARD\r\nEND:VTIMEZONE\r\n"
                + "BEGIN:VEVENT\r\nUID:c1\r\nSUMMARY:Lesson\r\n"
                + "DTSTART;TZID=Customized Time Zone:20260105T080000\r\nRRULE:FREQ=WEEKLY\r\nEND:VEVENT\r\n"
                + "END:VCALENDAR\r\n";

        var entry = importer.parse(ics).getFirst();

        assertThat(entry.timeZone()).isEqualTo("UTC");
        assertThat(entry.localStart()).isEqualTo("2026-01-05T07:00");
    }

    @Test
    void anEventWithoutAStartIsSkipped() {
        var parsed = importer.read(calendar("UID:n1", "SUMMARY:Nowhen"));

        assertThat(parsed.entries()).isEmpty();
        assertThat(parsed.unreadable()).containsExactly("n1");
    }

    // RFC 5545, 3.8.1.11: a called-off meeting stood in the calendar as if it took place.
    @Test
    void aCancelledEventIsNoEvent() {
        var parsed = importer.read(calendar(
                "UID:c1", "SUMMARY:Parents' evening", "STATUS:CANCELLED", "DTSTART:20261012T170000Z"));

        assertThat(parsed.entries()).isEmpty();
        assertThat(parsed.unreadable()).isEmpty();
    }

    // Google writes a cancelled occurrence as an override with STATUS:CANCELLED, not as
    // an EXDATE.
    @Test
    void aCancelledOverrideCancelsItsOccurrence() {
        String ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//EN\r\n"
                + "BEGIN:VEVENT\r\nUID:s1\r\nSUMMARY:Lesson\r\n"
                + "DTSTART;TZID=Europe/Berlin:20261005T080000\r\nRRULE:FREQ=WEEKLY\r\nEND:VEVENT\r\n"
                + "BEGIN:VEVENT\r\nUID:s1\r\nSUMMARY:Lesson\r\nSTATUS:CANCELLED\r\n"
                + "RECURRENCE-ID;TZID=Europe/Berlin:20261012T080000\r\n"
                + "DTSTART;TZID=Europe/Berlin:20261012T080000\r\nEND:VEVENT\r\n"
                + "BEGIN:VEVENT\r\nUID:s2\r\nSUMMARY:Choir\r\nSTATUS:CANCELLED\r\n"
                + "RECURRENCE-ID;TZID=Europe/Berlin:20261012T190000\r\n"
                + "DTSTART;TZID=Europe/Berlin:20261012T190000\r\nEND:VEVENT\r\n"
                + "END:VCALENDAR\r\n";

        var entries = importer.parse(ics);

        assertThat(entries).hasSize(1);
        assertThat(entries.getFirst().exceptions()).containsEntry("2026-10-12T08:00", Map.of("cancelled", true));
    }

    @Test
    void anExcludedDateCancelsThatDaysOccurrence() {
        var entry = importer.parse(calendar(
                        "UID:s1",
                        "SUMMARY:Lesson",
                        "DTSTART;TZID=Europe/Berlin:20261005T080000",
                        "RRULE:FREQ=WEEKLY",
                        "EXDATE;VALUE=DATE:20261012"))
                .getFirst();

        assertThat(entry.exceptions()).containsEntry("2026-10-12T08:00", Map.of("cancelled", true));
    }

    // RFC 5545, 3.3.10: beside a start with a zone, UNTIL is a UTC instant. Read as its
    // midnight, a date lost the series its last day.
    @Test
    void aSeriesEndingOnADateKeepsThatDay() {
        var entry = importer.parse(calendar(
                        "UID:s1",
                        "SUMMARY:Holiday club",
                        "DTSTART;TZID=Europe/Berlin:20261005T090000",
                        "RRULE:FREQ=DAILY;UNTIL=20261010"))
                .getFirst();

        assertThat(entry.rrule()).isEqualTo("FREQ=DAILY;UNTIL=20261010T215959Z");
        assertThat(RecurrenceTestAccess.create().expand(
                        entry.rrule(),
                        java.time.LocalDateTime.parse(entry.localStart()),
                        entry.timeZone(),
                        java.time.LocalDateTime.parse("2026-10-01T00:00"),
                        java.time.LocalDateTime.parse("2026-11-01T00:00")))
                .hasSize(6)
                .last()
                .isEqualTo(java.time.LocalDateTime.parse("2026-10-10T09:00"));
    }

    @Test
    void aSeriesEndingAtATimeWithoutZoneEndsInItsOwn() {
        assertThat(IcsImporter.untilInUtc("FREQ=DAILY;UNTIL=20261010T090000;BYHOUR=9", java.time.ZoneId.of("Europe/Berlin")))
                .isEqualTo("FREQ=DAILY;UNTIL=20261010T070000Z;BYHOUR=9");
        assertThat(IcsImporter.untilInUtc("FREQ=DAILY;UNTIL=20261010T070000Z", java.time.ZoneId.of("Europe/Berlin")))
                .isEqualTo("FREQ=DAILY;UNTIL=20261010T070000Z");
    }

    @Test
    void anAllDayEndEqualToItsStartIsThatDay() {
        var entry = importer.parse(calendar(
                        "UID:d1", "SUMMARY:Fair", "DTSTART;VALUE=DATE:20261010", "DTEND;VALUE=DATE:20261010"))
                .getFirst();

        assertThat(entry.endDate()).isEqualTo(LocalDate.of(2026, 10, 10));
    }
}
