package de.danielkononov.hiwiski.calendar.internal;

import de.danielkononov.hiwiski.recurrence.Recurrence;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import net.fortuna.ical4j.model.TimeZoneRegistry;
import net.fortuna.ical4j.model.TimeZoneRegistryFactory;
import org.springframework.stereotype.Component;

/**
 * Writing ICS by hand.
 *
 * <p>"Write ICS by hand, read it with ical4j. <strong>Foreign files are the problem,
 * our own are not.</strong>" A library for writing would
 * bring a dependency with its own model, its own ideas about time zones and its own
 * surprises — for a file whose structure fits on one page.
 *
 * <p>Series go out as {@code RRULE}, <strong>not expanded</strong> — every client
 * handles that, and it keeps the file small.
 */
@Component
class IcsWriter {

    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(IcsWriter.class);

    private final Recurrence recurrence;

    IcsWriter(Recurrence recurrence) {
        this.recurrence = recurrence;
    }

    private static final DateTimeFormatter UTC_STAMP =
            DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'");

    private static final DateTimeFormatter LOCAL_STAMP = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss");

    private static final DateTimeFormatter DATE = DateTimeFormatter.ofPattern("yyyyMMdd");

    /** The name under which the calendar appears in the foreign program. */
    record Feed(String name, List<Entry> entries) {}

    /**
     * @param busyOnly free/busy only: title and location stay out
     */
    record Entry(
            String uid,
            String title,
            String description,
            String location,
            String timeForm,
            OffsetDateTime startsAt,
            OffsetDateTime endsAt,
            LocalDate startDate,
            LocalDate endDate,
            String localStart,
            String localEnd,
            String timeZone,
            String rrule,
            /**
             * The series' exceptions, as a JSON object -- keyed by the original start.
             */
            String exceptions,
            OffsetDateTime lastModified,
            boolean busyOnly) {}

    String write(Feed feed) {
        StringBuilder ics = new StringBuilder();
        line(ics, "BEGIN:VCALENDAR");
        line(ics, "VERSION:2.0");
        line(ics, "PRODID:-//hiwiski//DE");
        line(ics, "CALSCALE:GREGORIAN");
        line(ics, "METHOD:PUBLISH");
        line(ics, "X-WR-CALNAME:" + escape(feed.name()));
        timeZones(ics, feed.entries());

        for (Entry entry : feed.entries()) {
            if (!placeable(entry)) {
                // An event without the start of its time form cannot be written; one
                // such row must not cost the whole feed.
                continue;
            }
            // Each event is written apart and only then added: a row that fails half-way
            // (a stored value this writer cannot read) is left out, and the feed goes on.
            // An exception used to fail the whole feed for every subscriber.
            StringBuilder event = new StringBuilder();
            try {
                entry(event, entry);
            } catch (RuntimeException e) {
                log.warn("leaving event {} out of the feed: {}", entry.uid(), e.toString());
                continue;
            }
            ics.append(event);
        }

        line(ics, "END:VCALENDAR");
        return ics.toString();
    }

    private void entry(StringBuilder ics, Entry entry) {
        line(ics, "BEGIN:VEVENT");
        line(ics, "UID:" + entry.uid());
        line(ics, "DTSTAMP:" + UTC_STAMP.format(
                (entry.lastModified() == null ? OffsetDateTime.now(ZoneOffset.UTC) : entry.lastModified())
                        .withOffsetSameInstant(ZoneOffset.UTC)));

        String rrule = rule(entry);
        switch (entry.timeForm()) {
            case "ALL_DAY" -> {
                LocalDate start = entry.startDate();
                LocalDate end = entry.endDate() == null ? start : entry.endDate();
                LocalDate first = rrule == null
                        ? start
                        : firstOccurrence(rrule, start.atStartOfDay(), seriesZone(entry)).toLocalDate();
                // All-day is a date, not a point in time: January 1st is not at 23:00
                // the day before in Portugal.
                line(ics, "DTSTART;VALUE=DATE:" + DATE.format(first));
                // DTEND is exclusive in the standard.
                line(ics, "DTEND;VALUE=DATE:" + DATE.format(
                        first.plusDays(java.time.temporal.ChronoUnit.DAYS.between(start, end) + 1)));
            }
            case "RECURRING" -> {
                LocalDateTime start = LocalDateTime.parse(localStamp(entry.localStart()), LOCAL_STAMP);
                LocalDateTime first = rrule == null ? start : firstOccurrence(rrule, start, entry.timeZone());
                // With zone and local time: in UTC the series would shift when the
                // clocks change.
                line(ics, "DTSTART;TZID=" + entry.timeZone() + ":" + LOCAL_STAMP.format(first));
                String end = localStampOrNull(entry.localEnd());
                if (end != null) {
                    LocalDateTime moved = first.plus(
                            java.time.Duration.between(start, LocalDateTime.parse(end, LOCAL_STAMP)));
                    line(ics, "DTEND;TZID=" + entry.timeZone() + ":" + LOCAL_STAMP.format(moved));
                }
            }
            default -> {
                line(ics, "DTSTART:" + UTC_STAMP.format(entry.startsAt().withOffsetSameInstant(ZoneOffset.UTC)));
                if (entry.endsAt() != null) {
                    line(ics, "DTEND:" + UTC_STAMP.format(entry.endsAt().withOffsetSameInstant(ZoneOffset.UTC)));
                }
            }
        }

        if (rrule != null) {
            // Without the stripping, the file said `RRULE:RRULE:FREQ=WEEKLY` — the
            // client stores the rule with the prefix, the server without, and a
            // foreign program then does not read the series at all. Found when
            // importing an export into another calendar program.
            line(ics, "RRULE:" + ("ALL_DAY".equals(entry.timeForm()) ? untilAsDate(rrule, seriesZone(entry)) : rrule));
            // Cancelled single occurrences go out as EXDATE. Without them the foreign
            // program would show an event that no longer exists here -- and that is
            // exactly how you notice an export that is only almost right.
            String exdates = cancelled(entry);
            if (!exdates.isEmpty()) {
                line(ics, exdates);
            }
        }

        body(ics, entry);
        line(ics, "END:VEVENT");
        if (rrule != null) {
            moved(ics, entry);
        }
    }

    /**
     * {@code 2026-10-19T12:00} becomes {@code 20261019T120000}.
     *
     * <p><strong>With seconds.</strong> RFC 5545 requires {@code YYYYMMDDTHHMMSS}; a stamp
     * without seconds is not a valid value. The UI writes the local time to the minute,
     * and the file then said {@code DTSTART;TZID=Europe/Berlin:20261019T1200}.
     *
     * <p><strong>Parsed, not copied.</strong> The stamp used to be the stored text with
     * {@code -} and {@code :} removed, so a line break in it started a content line of
     * its own in every subscriber's calendar. A value
     * that is not a local date-time is not written at all.
     */
    private static String localStamp(String local) {
        String stamp = localStampOrNull(local);
        if (stamp == null) {
            throw new IllegalArgumentException("not a local date-time");
        }
        return stamp;
    }

    private static String localStampOrNull(String local) {
        if (local == null) {
            return null;
        }
        try {
            return LOCAL_STAMP.format(LocalDateTime.parse(local.trim().replace(' ', 'T')));
        } catch (DateTimeParseException e) {
            try {
                return LOCAL_STAMP.format(LocalDate.parse(local.trim()).atStartOfDay());
            } catch (DateTimeParseException alsoNot) {
                return null;
            }
        }
    }

    /**
     * The rule as it goes into the file, or {@code null} if there is none to write.
     *
     * <p>Only the characters a rule is made of: a rule that came with a line break or a
     * colon carried its own content lines into the feed (M13). Sync refuses such a rule
     * on the way in; this is the second line for rows written before that.
     */
    private static String rule(Entry entry) {
        if (entry.rrule() == null || entry.rrule().isBlank()) {
            return null;
        }
        if (!"RECURRING".equals(entry.timeForm()) && !"ALL_DAY".equals(entry.timeForm())) {
            // A moment with a rule is shown once, in the app and by the server, which
            // expand only series on the wall clock and of whole days. Written with its
            // rule, it repeated in every subscriber's calendar and nowhere here.
            return null;
        }
        String rule = stripPrefix(entry.rrule().trim());
        return RULE_CHARACTERS.matcher(rule).matches() ? rule : null;
    }

    private static final java.util.regex.Pattern RULE_CHARACTERS =
            java.util.regex.Pattern.compile("[A-Za-z0-9=;,+\\-]+");

    /** How far ahead the first occurrence of a series is looked for -- step by step. */
    private static final List<java.time.Period> FIRST_OCCURRENCE_WITHIN =
            List.of(java.time.Period.ofMonths(2), java.time.Period.ofYears(2), java.time.Period.ofYears(12));

    /**
     * Where a series begins in the file: its first occurrence.
     *
     * <p>A start the rule does not hold -- a file from Outlook, a series moved in the week
     * view before its start followed the rule -- is left out here, on both sides
     * ({@code golden/recurrence.json}). RFC 5545 calls such a series undefined and its
     * DTSTART the first instance (3.8.5.3): written as it is stored, other programs may
     * show one occurrence more than the app. The first one the rule yields is the same
     * series in every reading; {@code COUNT} does not count the start that is left out.
     * A rule without any occurrence in sight keeps its start.
     */
    private LocalDateTime firstOccurrence(String rrule, LocalDateTime start, String zone) {
        try {
            if (!recurrence.accepts(rrule)) {
                return start;
            }
            for (java.time.Period within : FIRST_OCCURRENCE_WITHIN) {
                List<LocalDateTime> found = recurrence.expand(rrule, start, zone, start, start.plus(within));
                if (!found.isEmpty()) {
                    return found.getFirst();
                }
            }
        } catch (RuntimeException e) {
            // A rule or zone the library will not take: the event goes out as it is.
            log.debug("first occurrence of a series not found: {}", e.toString());
        }
        return start;
    }

    /** The zone a series is expanded in -- one of whole days may have none. */
    private static String seriesZone(Entry entry) {
        return validZone(entry.timeZone()) ? entry.timeZone() : "UTC";
    }

    /**
     * A series of whole days ends on a date: RFC 5545 wants {@code UNTIL} in the value
     * type of DTSTART (3.3.10). The app writes the end of the chosen day as a UTC
     * instant; in the series' zone its date is that day. A strict reader refused the
     * rule, or the whole feed.
     */
    static String untilAsDate(String rrule, String zone) {
        var until = UNTIL_DATE_TIME.matcher(rrule);
        if (!until.find()) {
            return rrule;
        }
        LocalDateTime stamp = LocalDateTime.parse(until.group(1).toUpperCase(java.util.Locale.ROOT), LOCAL_STAMP);
        LocalDate day = until.group(2).isEmpty()
                ? stamp.toLocalDate()
                : stamp.atOffset(ZoneOffset.UTC).atZoneSameInstant(ZoneId.of(zone)).toLocalDate();
        return rrule.substring(0, until.start()) + "UNTIL=" + DATE.format(day) + rrule.substring(until.end());
    }

    /** An {@code UNTIL} with a time: UTC with {@code Z}, local without. */
    private static final java.util.regex.Pattern UNTIL_DATE_TIME =
            java.util.regex.Pattern.compile("(?i)UNTIL=(\\d{8}T\\d{6})(Z?)");

    /** What the event says -- or, free/busy only, that there is something. */
    private static void body(StringBuilder ics, Entry entry) {
        if (entry.busyOnly()) {
            // "free/busy only": grandma sees that there is something, not what.
            line(ics, "SUMMARY:Busy");
            line(ics, "TRANSP:OPAQUE");
            line(ics, "CLASS:PRIVATE");
        } else {
            line(ics, "SUMMARY:" + escape(entry.title()));
            if (entry.description() != null && !entry.description().isBlank()) {
                line(ics, "DESCRIPTION:" + escape(entry.description()));
            }
            if (entry.location() != null && !entry.location().isBlank()) {
                line(ics, "LOCATION:" + escape(entry.location()));
            }
        }
    }

    /**
     * Every moved occurrence of a series as its own VEVENT: same UID, the original start
     * as RECURRENCE-ID. Without them a lesson moved from 16:00 to 17:00 here still showed
     * at 16:00 in the subscribed calendar.
     */
    @SuppressWarnings("unchecked")
    private static void moved(StringBuilder ics, Entry entry) {
        if (entry.exceptions() == null || entry.exceptions().isBlank()) {
            return;
        }
        Map<String, Object> exceptions;
        try {
            exceptions = new tools.jackson.databind.ObjectMapper().readValue(entry.exceptions(), Map.class);
        } catch (RuntimeException e) {
            return;
        }
        boolean allDay = "ALL_DAY".equals(entry.timeForm());
        for (var exception : new java.util.TreeMap<>(exceptions).entrySet()) {
            if (!(exception.getValue() instanceof Map<?, ?> move)
                    || !(move.get("start") instanceof String start)
                    || Boolean.TRUE.equals(move.get("cancelled"))) {
                continue;
            }
            String end = move.get("end") instanceof String value ? value : start;
            if (!writable(exception.getKey(), start, end)) {
                // Not a date-time: written as it stood, it was a way into the file (M13).
                continue;
            }
            line(ics, "BEGIN:VEVENT");
            line(ics, "UID:" + entry.uid());
            line(ics, "DTSTAMP:" + UTC_STAMP.format(
                    (entry.lastModified() == null ? OffsetDateTime.now(ZoneOffset.UTC) : entry.lastModified())
                            .withOffsetSameInstant(ZoneOffset.UTC)));
            if (allDay) {
                line(ics, "RECURRENCE-ID;VALUE=DATE:" + day(exception.getKey()));
                line(ics, "DTSTART;VALUE=DATE:" + day(start));
                line(ics, "DTEND;VALUE=DATE:" + DATE.format(localDay(end).plusDays(1)));
            } else {
                line(ics, "RECURRENCE-ID;TZID=" + entry.timeZone() + ":" + localStamp(exception.getKey()));
                line(ics, "DTSTART;TZID=" + entry.timeZone() + ":" + localStamp(start));
                line(ics, "DTEND;TZID=" + entry.timeZone() + ":" + localStamp(end));
            }
            body(ics, entry);
            line(ics, "END:VEVENT");
        }
    }

    private static boolean writable(String... locals) {
        for (String local : locals) {
            if (localStampOrNull(local) == null) {
                return false;
            }
        }
        return true;
    }

    private static String day(String local) {
        return DATE.format(localDay(local));
    }

    /**
     * The day of a local date or date-time, parsed: the first ten characters of
     * {@code +10000-01-01} are no date.
     */
    private static LocalDate localDay(String local) {
        String value = local.trim().replace(' ', 'T');
        try {
            return LocalDateTime.parse(value).toLocalDate();
        } catch (DateTimeParseException e) {
            return LocalDate.parse(value);
        }
    }

    private static final TimeZoneRegistry ZONES = TimeZoneRegistryFactory.getInstance().createRegistry();

    /**
     * A VTIMEZONE for every zone a series names. RFC 5545 requires one per TZID, and
     * strict clients -- older Outlook -- took the times as floating without it, so
     * series showed shifted.
     */
    private static void timeZones(StringBuilder ics, List<Entry> entries) {
        entries.stream()
                .filter(entry -> "RECURRING".equals(entry.timeForm()) && validZone(entry.timeZone()))
                .map(Entry::timeZone)
                .distinct()
                .sorted()
                .forEach(id -> {
                    var zone = ZONES.getTimeZone(id);
                    if (zone == null) {
                        return;
                    }
                    // The block under the very TZID the events use -- the registry
                    // answers "UTC" with "Etc/UTC".
                    ics.append(zone.getVTimeZone()
                            .toString()
                            .replaceFirst("TZID:[^\r\n]*", Matcher.quoteReplacement("TZID:" + id)));
                });
    }

    private static boolean placeable(Entry entry) {
        return switch (entry.timeForm()) {
            case "ALL_DAY" -> entry.startDate() != null;
            // The zone goes into a TZID parameter, the start into DTSTART: both only as
            // what they claim to be (M13).
            case "RECURRING" -> localStampOrNull(entry.localStart()) != null && validZone(entry.timeZone());
            default -> entry.startsAt() != null;
        };
    }

    private static boolean validZone(String id) {
        return id != null && ZoneId.getAvailableZoneIds().contains(id);
    }

    /** A rule may arrive with or without {@code RRULE:}. In the file it appears exactly once. */
    private static String stripPrefix(String rrule) {
        return rrule.regionMatches(true, 0, "RRULE:", 0, 6) ? rrule.substring(6) : rrule;
    }

    /**
     * The cancelled occurrences as an {@code EXDATE} line, or empty.
     *
     * <p>Read from the JSON by hand and not through a mapper: the object has exactly one
     * shape, and a mapper here would be a dependency for a string search.
     */
    private static String cancelled(Entry entry) {
        if (entry.exceptions() == null || entry.exceptions().isBlank()) {
            return "";
        }
        var matcher = CANCELLED.matcher(entry.exceptions());
        var dates = new java.util.ArrayList<String>();
        while (matcher.find()) {
            dates.add(localStamp(matcher.group(1)));
        }
        if (dates.isEmpty()) {
            return "";
        }
        if ("ALL_DAY".equals(entry.timeForm())) {
            // A series of whole days excludes days, like its DTSTART -- with a zone and a
            // time, the foreign program matched none of them.
            return "EXDATE;VALUE=DATE:" + String.join(",", dates.stream().map(date -> date.substring(0, 8)).toList());
        }
        if (!validZone(entry.timeZone())) {
            return "";
        }
        // With a zone, like DTSTART: a series is tied to the wall clock.
        return "EXDATE;TZID=" + entry.timeZone() + ":" + String.join(",", dates);
    }

    /** Key of an entry with {@code "cancelled": true} -- the rest stays here. */
    private static final java.util.regex.Pattern CANCELLED = java.util.regex.Pattern.compile(
            "\"(\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2})\"\\s*:\\s*\\{[^}]*\"cancelled\"\\s*:\\s*true");

    /**
     * Lines longer than 75 octets are folded.
     *
     * <p>RFC 5545 requires it, and some programs otherwise fail on a long title — a bug
     * that only occurs with long titles and is therefore noticed late.
     */
    private static void line(StringBuilder ics, String raw) {
        // No line ends inside a line, whatever slipped through: a CR or LF here starts a
        // property of its own in the subscriber's calendar (M13). TEXT values have
        // theirs escaped by then; nothing else has any business with control characters.
        String value = CONTROL.matcher(raw).replaceAll("");
        byte[] bytes = value.getBytes(java.nio.charset.StandardCharsets.UTF_8);
        if (bytes.length <= 75) {
            ics.append(value).append("\r\n");
            return;
        }
        int written = 0;
        boolean first = true;
        while (written < bytes.length) {
            int limit = Math.min(first ? 75 : 74, bytes.length - written);
            // Do not split in the middle of a multi-byte character. The check only
            // applies where another byte follows at all -- at the end of the string
            // there is no split point left to move.
            while (limit > 1 && written + limit < bytes.length && (bytes[written + limit] & 0xC0) == 0x80) {
                limit--;
            }
            if (!first) {
                ics.append(' ');
            }
            ics.append(new String(bytes, written, limit, java.nio.charset.StandardCharsets.UTF_8)).append("\r\n");
            written += limit;
            first = false;
        }
    }

    private static final java.util.regex.Pattern CONTROL =
            java.util.regex.Pattern.compile("[\\x00-\\x08\\x0A-\\x1F\\x7F]");

    private static String escape(String value) {
        if (value == null) {
            return "";
        }
        // Every line break as \n: a raw CR in a content line made Outlook and iOS split
        // the line or reject the feed.
        return value.replace("\r\n", "\n")
                .replace("\r", "\n")
                .replace("\\", "\\\\")
                .replace(";", "\\;")
                .replace(",", "\\,")
                .replace("\n", "\\n");
    }
}
