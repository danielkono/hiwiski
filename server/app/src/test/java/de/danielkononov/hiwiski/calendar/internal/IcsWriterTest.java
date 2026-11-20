package de.danielkononov.hiwiski.calendar.internal;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.recurrence.internal.RecurrenceTestAccess;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

/** What goes out in a feed. */
class IcsWriterTest {

    private final IcsWriter writer = new IcsWriter(RecurrenceTestAccess.create());

    @Test
    void aSeriesOfWholeDaysExcludesDays() {
        var entry = new IcsWriter.Entry(
                "e1", "Anna", null, null, "ALL_DAY", null, null,
                LocalDate.of(2020, 3, 14), LocalDate.of(2020, 3, 14),
                null, null, "Europe/Berlin", "FREQ=YEARLY",
                "{\"2026-03-14T00:00\": {\"cancelled\": true}}", null, false);

        String ics = writer.write(new IcsWriter.Feed("Family", List.of(entry)));

        assertThat(ics).contains("EXDATE;VALUE=DATE:20260314\r\n");
        // ...and a foreign library reads the same.
        assertThat(new IcsImporter(RecurrenceTestAccess.create()).parse(ics).getFirst().rrule()).isEqualTo("FREQ=YEARLY");
    }

    @Test
    void anEventWithoutAStartDoesNotBreakTheFeed() {
        var broken = new IcsWriter.Entry(
                "e1", "Broken", null, null, "TIMED", null, null, null, null, null, null, null, null, null, null,
                false);
        var fine = new IcsWriter.Entry(
                "e2", "Dentist", null, null, "TIMED",
                java.time.OffsetDateTime.parse("2026-10-12T08:00:00Z"), null,
                null, null, null, null, null, null, null, null, false);

        String ics = writer.write(new IcsWriter.Feed("Family", List.of(broken, fine)));

        assertThat(ics).contains("UID:e2").doesNotContain("UID:e1");
    }

    // One unreadable key failed the feed for everyone.
    @Test
    void anEventTheWriterCannotReadCostsOnlyThatEvent() {
        var impossibleDay = new IcsWriter.Entry(
                "e1", "Swimming", null, null, "RECURRING", null, null, null, null,
                "2026-01-05T17:00", "2026-01-05T18:00", "Europe/Berlin", "FREQ=WEEKLY",
                "{\"2026-02-30T17:00\": {\"cancelled\": true}}", null, false);
        var extendedYear = new IcsWriter.Entry(
                "e2", "Anna", null, null, "ALL_DAY", null, null,
                LocalDate.of(2020, 3, 14), LocalDate.of(2020, 3, 14),
                null, null, "Europe/Berlin", "FREQ=YEARLY",
                "{\"+10000-01-01\": {\"start\": \"+10000-01-01\"}}", null, false);
        var fine = new IcsWriter.Entry(
                "e3", "Dentist", null, null, "TIMED",
                java.time.OffsetDateTime.parse("2026-10-12T08:00:00Z"), null,
                null, null, null, null, null, null, null, null, false);

        String ics = writer.write(new IcsWriter.Feed("Family", List.of(impossibleDay, extendedYear, fine)));

        assertThat(ics).contains("UID:e3").doesNotContain("UID:e1").endsWith("END:VCALENDAR\r\n");
        assertThat(ics.split("BEGIN:VEVENT", -1).length - 1)
                .describedAs("no half-written event is left in the file")
                .isEqualTo(ics.split("END:VEVENT", -1).length - 1);
    }

    @Test
    void aLineBreakFromWindowsIsEscapedWhole() {
        var entry = new IcsWriter.Entry(
                "e1", "Dentist", "Bring\r\nthe card\rplease", null, "TIMED",
                java.time.OffsetDateTime.parse("2026-10-12T08:00:00Z"), null,
                null, null, null, null, null, null, null, null, false);

        String ics = writer.write(new IcsWriter.Feed("Family", List.of(entry)));

        assertThat(ics).contains("DESCRIPTION:Bring\\nthe card\\nplease\r\n");
    }

    @Test
    void everyZoneASeriesNamesIsDefinedInTheFile() {
        var entry = new IcsWriter.Entry(
                "e1", "Swimming", null, null, "RECURRING", null, null, null, null,
                "2026-01-05T17:00", "2026-01-05T18:00", "Europe/Berlin", "FREQ=WEEKLY", null, null, false);

        String ics = writer.write(new IcsWriter.Feed("Family", List.of(entry, entry)));

        assertThat(ics).containsOnlyOnce("BEGIN:VTIMEZONE\r\nTZID:Europe/Berlin\r\n");
        assertThat(ics.indexOf("BEGIN:VTIMEZONE")).isLessThan(ics.indexOf("BEGIN:VEVENT"));
        // ...and a foreign library still reads the series in that zone.
        assertThat(new IcsImporter(RecurrenceTestAccess.create()).parse(ics).getFirst().timeZone()).isEqualTo("Europe/Berlin");
    }

    @Test
    void aMovedOccurrenceGoesOutAsAnOverride() {
        var entry = new IcsWriter.Entry(
                "e1", "Swimming", null, null, "RECURRING", null, null, null, null,
                "2026-10-05T16:00", "2026-10-05T17:00", "Europe/Berlin", "FREQ=WEEKLY",
                "{\"2026-10-12T16:00\": {\"start\": \"2026-10-12T17:00\", \"end\": \"2026-10-12T18:00\"}}",
                null, false);

        String ics = writer.write(new IcsWriter.Feed("Family", List.of(entry)));

        assertThat(ics).contains("RECURRENCE-ID;TZID=Europe/Berlin:20261012T160000\r\n"
                + "DTSTART;TZID=Europe/Berlin:20261012T170000\r\n"
                + "DTEND;TZID=Europe/Berlin:20261012T180000\r\n");
        // A foreign library folds it back into the series.
        var read = new IcsImporter(RecurrenceTestAccess.create()).parse(ics);
        assertThat(read).hasSize(1);
        assertThat(read.getFirst().exceptions())
                .containsEntry("2026-10-12T16:00", Map.of("start", "2026-10-12T17:00", "end", "2026-10-12T18:00"));
    }

    // Rows written before sync checked these fields.
    private static final String FORGED = "\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:forged@hiwiski\r\nSUMMARY:Pickup moved";

    @Test
    void aRuleWithLinesOfItsOwnIsNotWritten() {
        var entry = new IcsWriter.Entry(
                "e1", "Swimming", null, null, "RECURRING", null, null, null, null,
                "2026-10-05T16:00", "2026-10-05T17:00", "Europe/Berlin", "FREQ=DAILY" + FORGED, null, null, true);

        String ics = writer.write(new IcsWriter.Feed("Family", List.of(entry)));

        assertThat(ics).doesNotContain("forged").doesNotContain("RRULE:FREQ=DAILY").contains("UID:e1");
    }

    @Test
    void aZoneOrStartWithLinesOfItsOwnCostsOnlyThatEvent() {
        var zone = new IcsWriter.Entry(
                "e1", "Swimming", null, null, "RECURRING", null, null, null, null,
                "2026-10-05T16:00", null, "Europe/Berlin" + FORGED, "FREQ=WEEKLY", null, null, false);
        var start = new IcsWriter.Entry(
                "e2", "Swimming", null, null, "RECURRING", null, null, null, null,
                "2026-10-05T16:00" + FORGED, null, "Europe/Berlin", "FREQ=WEEKLY", null, null, false);
        var end = new IcsWriter.Entry(
                "e3", "Swimming", null, null, "RECURRING", null, null, null, null,
                "2026-10-05T16:00", "2026-10-05T17:00" + FORGED, "Europe/Berlin", "FREQ=WEEKLY", null, null, false);

        String ics = writer.write(new IcsWriter.Feed("Family", List.of(zone, start, end)));

        assertThat(ics).doesNotContain("forged").doesNotContain("UID:e1").doesNotContain("UID:e2").contains("UID:e3");
    }

    @Test
    void anExceptionWithLinesOfItsOwnIsNotWritten() {
        var entry = new IcsWriter.Entry(
                "e1", "Swimming", null, null, "RECURRING", null, null, null, null,
                "2026-10-05T16:00", "2026-10-05T17:00", "Europe/Berlin", "FREQ=WEEKLY",
                "{\"2026-10-12T16:00" + FORGED.replace("\r\n", "\\r\\n") + "\": {\"start\": \"2026-10-12T17:00\"},"
                        + " \"2026-10-19T16:00\": {\"start\": \"2026-10-19T17:00\\r\\nATTACH:x\"}}",
                null, false);

        String ics = writer.write(new IcsWriter.Feed("Family", List.of(entry)));

        assertThat(ics).doesNotContain("forged").doesNotContain("ATTACH").doesNotContain("RECURRENCE-ID");
    }

    // The app and the server show a moment once; written with its rule, it repeated in
    // every subscriber's calendar.
    @Test
    void aMomentGoesOutOnceWhateverRuleItCarries() {
        var entry = new IcsWriter.Entry(
                "e1", "Dentist", null, null, "TIMED",
                java.time.OffsetDateTime.parse("2026-10-12T08:00:00Z"), null,
                null, null, null, null, null, "FREQ=WEEKLY", "{\"2026-10-19T10:00\": {\"cancelled\": true}}",
                null, false);

        String ics = writer.write(new IcsWriter.Feed("Family", List.of(entry)));

        assertThat(ics).contains("UID:e1").doesNotContain("RRULE").doesNotContain("EXDATE");
    }

    // RFC 5545, 3.3.10: UNTIL has the value type of DTSTART. The app writes the end of
    // the chosen day as a UTC instant.
    @org.junit.jupiter.params.ParameterizedTest
    @org.junit.jupiter.params.provider.CsvSource({
        "Europe/Berlin, 20261231T225959Z",
        "America/New_York, 20270101T045959Z",
    })
    void aSeriesOfWholeDaysEndsOnADate(String zone, String until) {
        var entry = new IcsWriter.Entry(
                "e1", "Market", null, null, "ALL_DAY", null, null,
                LocalDate.of(2026, 10, 3), LocalDate.of(2026, 10, 3),
                null, null, zone, "FREQ=WEEKLY;BYDAY=SA;UNTIL=" + until + ";WKST=MO", null, null, false);

        String ics = writer.write(new IcsWriter.Feed("Family", List.of(entry)));

        assertThat(ics).contains("RRULE:FREQ=WEEKLY;BYDAY=SA;UNTIL=20261231;WKST=MO\r\n");
    }

    // RFC 5545, 3.8.5.3: a DTSTART the rule does not hold makes the series undefined.
    // The app leaves such a start out; other programs may show it.
    @Test
    void aSeriesStartsOnItsFirstOccurrence() {
        var timed = new IcsWriter.Entry(
                "e1", "Football", null, null, "RECURRING", null, null, null, null,
                "2026-10-06T09:00", "2026-10-06T10:30", "Europe/Berlin", "FREQ=WEEKLY;BYDAY=MO;COUNT=3", null,
                null, false);
        var wholeDays = new IcsWriter.Entry(
                "e2", "Camp", null, null, "ALL_DAY", null, null,
                LocalDate.of(2026, 10, 6), LocalDate.of(2026, 10, 7),
                null, null, "Europe/Berlin", "FREQ=WEEKLY;BYDAY=SA", null, null, false);

        String ics = writer.write(new IcsWriter.Feed("Family", List.of(timed, wholeDays)));

        assertThat(ics).contains("DTSTART;TZID=Europe/Berlin:20261012T090000\r\n"
                + "DTEND;TZID=Europe/Berlin:20261012T103000\r\n"
                + "RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=3\r\n");
        assertThat(ics).contains("DTSTART;VALUE=DATE:20261010\r\nDTEND;VALUE=DATE:20261012\r\n");
    }

    @Test
    void noLineCarriesALineBreakOfItsOwn() {
        var entry = new IcsWriter.Entry(
                "e1\r\nATTACH:x", "Dentist", null, null, "TIMED",
                java.time.OffsetDateTime.parse("2026-10-12T08:00:00Z"), null,
                null, null, null, null, null, null, null, null, false);

        String ics = writer.write(new IcsWriter.Feed("Family", List.of(entry)));

        assertThat(ics).doesNotContain("\r\nATTACH");
    }
}
