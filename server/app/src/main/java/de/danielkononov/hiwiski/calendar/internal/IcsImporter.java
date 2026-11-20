package de.danielkononov.hiwiski.calendar.internal;

import de.danielkononov.hiwiski.recurrence.Recurrence;
import java.io.StringReader;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.time.temporal.Temporal;
import java.util.ArrayList;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import net.fortuna.ical4j.data.CalendarBuilder;
import net.fortuna.ical4j.model.Calendar;
import net.fortuna.ical4j.model.component.VEvent;
import net.fortuna.ical4j.model.property.ExDate;
import net.fortuna.ical4j.model.property.RecurrenceId;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * Reading foreign ICS files — with ical4j.
 *
 * <p>"Write ICS by hand, read it with ical4j. <strong>Foreign files are the problem,
 * our own are not.</strong>" What comes from the network
 * follows no standard as closely as one hopes: missing time zones, DTEND without
 * DTSTART, lines nobody expects.
 */
@Component
class IcsImporter {

    private static final Logger log = LoggerFactory.getLogger(IcsImporter.class);

    private final Recurrence recurrence;

    IcsImporter(Recurrence recurrence) {
        this.recurrence = recurrence;
    }

    /**
     * The rule of a foreign event, if it is one that may be stored -- otherwise none,
     * and the event comes in as a single one at its start.
     *
     * <p>The same check as on sync. Rules from a feed used to be stored as they came: a
     * subscribed school calendar could deliver {@code FREQ=SECONDLY} or a rule the
     * devices search through for minutes, to every member who sees the calendar.
     * One such event costs its repetition, not the
     * import.
     */
    private String storableRule(String uid, String rrule) {
        if (rrule == null || rrule.isBlank()) {
            return null;
        }
        if (EventFieldCheck.acceptable(Map.of("rrule", rrule), recurrence)) {
            return rrule;
        }
        log.info("importing event {} without its rule, which cannot be stored", uid);
        return null;
    }

    /**
     * An event from a foreign file.
     *
     * <p>{@code uid} and {@code recurrenceId} are the key: <strong>matching is by UID
     * plus RECURRENCE-ID, never by title</strong>. A title changes,
     * and then the event would show up twice.
     */
    record Entry(
            String uid,
            String recurrenceId,
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
             * Cancelled ({@code EXDATE}) and moved ({@code RECURRENCE-ID}) occurrences of
             * a series, in the model's shape: keyed by the original local start.
             */
            Map<String, Object> exceptions,
            /** For an override: the occurrence it replaces, as the file states it. */
            Temporal original,
            // STATUS:CANCELLED -- for an override, the occurrence is cancelled.
            boolean cancelled) {

        Entry withExceptions(Map<String, Object> exceptions) {
            return new Entry(uid, recurrenceId, title, description, location, timeForm, startsAt, endsAt,
                    startDate, endDate, localStart, localEnd, timeZone, rrule, exceptions, original, cancelled);
        }
    }

    /** The calendar's own name ({@code X-WR-CALNAME}), as a suggestion for ours. */
    Optional<String> calendarName(String ics) {
        try {
            Calendar calendar = new CalendarBuilder().build(new StringReader(ics));
            return calendar.getProperty("X-WR-CALNAME")
                    .map(property -> property.getValue())
                    .map(String::trim)
                    .filter(name -> !name.isEmpty());
        } catch (Exception e) {
            return Optional.empty();
        }
    }

    /**
     * What a file held: the events read, and the UIDs of those that could not be read.
     *
     * @param unreadable UIDs of skipped events; {@code anonymous} is set when a skipped
     *     one had no UID at all, so it is unknown which event it was
     */
    record Parsed(List<Entry> entries, java.util.Set<String> unreadable, boolean anonymous) {}

    List<Entry> parse(String ics) {
        return read(ics).entries();
    }

    Parsed read(String ics) {
        Calendar calendar;
        try {
            calendar = new CalendarBuilder().build(new StringReader(withIanaZones(ics)));
        } catch (Exception e) {
            throw de.danielkononov.hiwiski.platform.HiwiskiException.invalid("calendar.ics_unreadable");
        }

        List<Entry> entries = new ArrayList<>();
        java.util.Set<String> unreadable = new java.util.HashSet<>();
        boolean anonymous = false;
        for (var component : calendar.getComponents("VEVENT")) {
            if (!(component instanceof VEvent event)) {
                continue;
            }
            try {
                Entry entry = toEntry(event);
                if (entry.cancelled() && entry.recurrenceId() == null) {
                    // A cancelled event is no event (RFC 5545, 3.8.1.11). Read as one, a
                    // called-off meeting stood in the calendar as if it took place; left
                    // out, a subscription removes it like any event that has gone.
                    continue;
                }
                entries.add(entry);
            } catch (RuntimeException e) {
                // A single broken event must not cost the whole file. The rest is
                // usable, and the count on the subscription says how many arrived.
                log.debug("skipping unreadable VEVENT", e);
                Optional<String> uid = value(event, "UID");
                uid.ifPresent(unreadable::add);
                anonymous |= uid.isEmpty();
            }
        }
        return new Parsed(withOverrides(entries), unreadable, anonymous);
    }

    /**
     * The file with every TZID parameter that names a known zone in another way --
     * Windows, a Mozilla path -- rewritten to its IANA ID ({@link TimeZoneIds}).
     *
     * <p>Before ical4j reads it: ical4j throws for a path, and for a Windows name makes
     * up a zone of its own. A TZID that cannot be resolved stays as it is.
     */
    static String withIanaZones(String ics) {
        String unfolded = FOLD.matcher(ics).replaceAll("");
        return TZID.matcher(unfolded).replaceAll(match -> {
            String raw = match.group(2);
            String name = raw.startsWith("\"") && raw.endsWith("\"") && raw.length() > 1
                    ? raw.substring(1, raw.length() - 1)
                    : raw;
            return java.util.regex.Matcher.quoteReplacement(TimeZoneIds.resolve(name)
                    .map(zone -> match.group(1) + zone.getId())
                    .orElse(match.group(0)));
        });
    }

    /** A folded line goes on after a line break and one space or tab (RFC 5545, 3.1). */
    private static final java.util.regex.Pattern FOLD = java.util.regex.Pattern.compile("\r?\n[ \t]");

    private static final java.util.regex.Pattern TZID =
            java.util.regex.Pattern.compile("(;TZID=)(\"[^\"]*\"|[^:;\r\n]*)");

    /**
     * Folds every override ({@code RECURRENCE-ID}) into its series as a moved occurrence.
     *
     * <p>Stored as an event of its own, the override showed next to the occurrence the
     * series still produced: a lesson moved from 08:00 to 10:00 showed twice. One
     * without its series in the file stays an event of its own.
     */
    private static List<Entry> withOverrides(List<Entry> entries) {
        Map<String, Entry> series = new LinkedHashMap<>();
        for (Entry entry : entries) {
            if (entry.recurrenceId() == null && entry.rrule() != null) {
                series.put(entry.uid(), entry);
            }
        }
        List<Entry> standalone = new ArrayList<>();
        for (Entry entry : entries) {
            Entry master = entry.recurrenceId() == null ? null : series.get(entry.uid());
            Optional<Map.Entry<String, Object>> moved =
                    master == null ? Optional.empty() : movedOccurrence(master, entry);
            if (moved.isEmpty()) {
                // A cancelled occurrence of a series that is not in the file cancels
                // nothing here, and is no event either.
                if (!entry.cancelled()) {
                    standalone.add(entry);
                }
                continue;
            }
            Map<String, Object> exceptions = new LinkedHashMap<>(master.exceptions());
            exceptions.put(moved.get().getKey(), moved.get().getValue());
            master = master.withExceptions(exceptions);
            series.put(master.uid(), master);
        }
        return standalone.stream()
                .map(entry -> entry.recurrenceId() == null && entry.rrule() != null ? series.get(entry.uid()) : entry)
                .toList();
    }

    /**
     * The override as an exception of the series: its original key and where it went --
     * or, cancelled, that it does not take place. Google writes a cancelled occurrence
     * this way rather than as an EXDATE, and it showed as if it took place.
     */
    private static Optional<Map.Entry<String, Object>> movedOccurrence(Entry master, Entry override) {
        if (override.original() == null) {
            return Optional.empty();
        }
        if (override.cancelled()) {
            String original = "ALL_DAY".equals(master.timeForm())
                    ? key(dateOf(override.original()))
                    : key(toLocal(override.original(), ZoneId.of(master.timeZone())));
            return Optional.of(Map.entry(original, Map.of("cancelled", true)));
        }
        if ("ALL_DAY".equals(master.timeForm())) {
            if (override.startDate() == null) {
                return Optional.empty();
            }
            return Optional.of(Map.entry(
                    key(dateOf(override.original())),
                    Map.of(
                            "start", key(override.startDate()),
                            "end", key(override.endDate() == null ? override.startDate() : override.endDate()))));
        }
        ZoneId zone = ZoneId.of(master.timeZone());
        LocalDateTime start = startOf(override, zone);
        if (start == null) {
            return Optional.empty();
        }
        LocalDateTime end = endOf(override, zone);
        Map<String, Object> move = new LinkedHashMap<>();
        move.put("start", key(start));
        move.put("end", key(end == null ? start : end));
        return Optional.of(Map.entry(key(toLocal(override.original(), zone)), move));
    }

    private static LocalDateTime startOf(Entry entry, ZoneId zone) {
        if (entry.startsAt() != null) {
            return entry.startsAt().atZoneSameInstant(zone).toLocalDateTime();
        }
        if (entry.localStart() != null) {
            return LocalDateTime.parse(entry.localStart())
                    .atZone(ZoneId.of(entry.timeZone()))
                    .withZoneSameInstant(zone)
                    .toLocalDateTime();
        }
        return null;
    }

    private static LocalDateTime endOf(Entry entry, ZoneId zone) {
        if (entry.endsAt() != null) {
            return entry.endsAt().atZoneSameInstant(zone).toLocalDateTime();
        }
        if (entry.localEnd() != null) {
            return LocalDateTime.parse(entry.localEnd())
                    .atZone(ZoneId.of(entry.timeZone()))
                    .withZoneSameInstant(zone)
                    .toLocalDateTime();
        }
        return null;
    }

    /** The key of an exception -- the local start to the minute, as the app writes it. */
    private static String key(LocalDateTime local) {
        return KEY.format(local);
    }

    private static String key(LocalDate date) {
        return key(date.atStartOfDay());
    }

    private static final DateTimeFormatter KEY = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm");

    private static LocalDate dateOf(Temporal value) {
        return value instanceof LocalDate date ? date : toLocal(value, ZoneOffset.UTC).toLocalDate();
    }

    /**
     * The cancelled occurrences of a series ({@code EXDATE}), in its own zone.
     *
     * @param time the series' time of day; {@code null} for a series of whole days
     */
    private static Map<String, Object> cancelled(VEvent event, ZoneId zone, LocalTime time) {
        Map<String, Object> exceptions = new LinkedHashMap<>();
        for (var property : event.getProperties("EXDATE")) {
            if (!(property instanceof ExDate<?> exdate)) {
                continue;
            }
            for (Temporal date : exdate.getDates()) {
                // RFC 5545 wants an EXDATE in the value type of DTSTART; some files
                // exclude a day from a series with a time, or a time from one of whole
                // days. Keyed as written, neither matched an occurrence, and the day
                // stayed in the calendar: it is the occurrence on that day.
                String key = switch (date) {
                    case LocalDate day when time != null -> key(day.atTime(time));
                    case LocalDate day -> key(day);
                    default -> time == null ? key(dayOf(date)) : key(toLocal(date, zone));
                };
                exceptions.put(key, Map.of("cancelled", true));
            }
        }
        return exceptions;
    }

    /** The date a date-time is written with -- in its own zone, or UTC for an instant. */
    private static LocalDate dayOf(Temporal value) {
        return switch (value) {
            case java.time.Instant instant -> instant.atZone(ZoneOffset.UTC).toLocalDate();
            default -> LocalDate.from(value);
        };
    }

    private Entry toEntry(VEvent event) {
        String uid = value(event, "UID").orElseThrow();
        String recurrenceId = value(event, "RECURRENCE-ID").orElse(null);
        Temporal original = event.getProperty("RECURRENCE-ID")
                .map(property -> (Temporal) ((RecurrenceId<?>) property).getDate())
                .orElse(null);
        String rule = value(event, "RRULE").orElse(null);
        boolean cancelled = value(event, "STATUS").map(status -> status.trim().equalsIgnoreCase("CANCELLED")).orElse(false);

        Temporal start = event.<Temporal>getStartDate().map(property -> property.getDate()).orElse(null);
        Temporal end = event.<Temporal>getEndDate().map(property -> property.getDate()).orElse(null);
        if (start == null) {
            // Without a start there is no event to place -- and stored as TIMED without
            // one, it broke the export of the whole feed. Skipped like any unreadable one.
            throw new IllegalArgumentException("VEVENT " + uid + " has no DTSTART");
        }
        Optional<ZoneId> named = event.<Temporal>getStartDate()
                .flatMap(property -> property.getParameter("TZID"))
                .map(parameter -> ((net.fortuna.ical4j.model.Parameter) parameter).getValue())
                .flatMap(TimeZoneIds::resolve);

        if (start instanceof LocalDate date) {
            String rrule = storableRule(uid, rule);
            // All-day is a date, not a point in time -- and with a rule a series of whole
            // days, which the app expands over dates.
            return new Entry(uid, recurrenceId, title(event), description(event), location(event),
                    "ALL_DAY", null, null, date,
                    // DTEND is exclusive in the standard; in the model end_date is the last day.
                    // Some feeds write DTEND equal to DTSTART: still the one day, never an end
                    // before the start.
                    end instanceof LocalDate endDate && endDate.isAfter(date) ? endDate.minusDays(1) : date,
                    null, null, null, rrule,
                    rrule == null ? Map.of() : cancelled(event, ZoneOffset.UTC, null), original, cancelled);
        }

        // Beside a start with a time, UNTIL is read in UTC before the rule is checked: a
        // date there was refused, and the series came in as a single event.
        ZoneId zone = named.orElse(start instanceof LocalDateTime ? ZoneId.systemDefault() : ZoneOffset.UTC);
        String rrule = rule == null ? null : storableRule(uid, untilInUtc(rule, zone));
        if (rrule != null) {
            // Every series is stored in local time, or it shifts when the clocks change
            // -- and only RECURRING is expanded at all: a UTC or
            // floating series stored as TIMED showed only its first occurrence. A UTC
            // one repeats in UTC; a floating one in the zone the rest of the import
            // assumes for it.
            // A zone that could not be resolved to an IANA ID keeps its instants, in UTC:
            // off by an hour across a clock change, but there -- it used to be skipped.
            String zoneId = zone.equals(ZoneOffset.UTC) ? "UTC" : zone.getId();
            LocalDateTime localStart = toLocal(start, zone);
            LocalDateTime localEnd = end == null ? null : toLocal(end, zone);
            return new Entry(uid, recurrenceId, title(event), description(event), location(event),
                    "RECURRING", null, null, null, null,
                    localStart.toString(), localEnd == null ? null : localEnd.toString(), zoneId, rrule,
                    cancelled(event, zone, localStart.toLocalTime()), original, cancelled);
        }

        return new Entry(uid, recurrenceId, title(event), description(event), location(event),
                "TIMED", toOffset(start), toOffset(end), null, null, null, null, null, rrule, Map.of(), original,
                cancelled);
    }

    /**
     * {@code UNTIL} as RFC 5545 wants it beside a start with a time: a UTC instant.
     *
     * <p>Some files end such a series on a date ({@code UNTIL=20261010}), or on a time
     * without a zone. Read as that date's midnight, the series lost its last day; a date
     * means that day, up to its end -- as the app writes "ends on" -- and a time without
     * a zone is one in the series' own.
     */
    static String untilInUtc(String rrule, ZoneId zone) {
        Matcher until = LOCAL_UNTIL.matcher(rrule);
        if (!until.find()) {
            return rrule;
        }
        LocalDateTime end = until.group(2) == null
                ? LocalDate.parse(until.group(1), BASIC_DATE).atTime(23, 59, 59)
                : LocalDateTime.parse(until.group(1) + until.group(2).toUpperCase(java.util.Locale.ROOT), BASIC_DATE_TIME);
        String instant = UTC_STAMP.format(end.atZone(zone).withZoneSameInstant(ZoneOffset.UTC));
        return rrule.substring(0, until.start()) + "UNTIL=" + instant + rrule.substring(until.end());
    }

    /** An {@code UNTIL} that is not a UTC instant: a date, or a date-time without {@code Z}. */
    private static final Pattern LOCAL_UNTIL =
            Pattern.compile("(?i)UNTIL=(\\d{8})(T\\d{6})?(?![0-9TZtz])");

    private static final DateTimeFormatter BASIC_DATE = DateTimeFormatter.ofPattern("yyyyMMdd");

    private static final DateTimeFormatter BASIC_DATE_TIME = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss");

    private static final DateTimeFormatter UTC_STAMP = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'");

    private static LocalDateTime toLocal(Temporal value, ZoneId zone) {
        return switch (value) {
            case LocalDateTime local -> local;
            case java.time.ZonedDateTime zoned -> zoned.withZoneSameInstant(zone).toLocalDateTime();
            case java.time.Instant instant -> instant.atZone(zone).toLocalDateTime();
            case OffsetDateTime offset -> offset.atZoneSameInstant(zone).toLocalDateTime();
            default -> LocalDateTime.from(value);
        };
    }

    private static OffsetDateTime toOffset(Temporal value) {
        if (value == null) {
            return null;
        }
        return switch (value) {
            case OffsetDateTime offset -> offset;
            case java.time.ZonedDateTime zoned -> zoned.toOffsetDateTime();
            case java.time.Instant instant -> instant.atOffset(ZoneOffset.UTC);
            // Without a zone, all that is left is an assumption. It lives here and not
            // scattered around: a file without a zone means the zone of whoever wrote it
            // -- and we do not know that.
            case LocalDateTime local -> local.atZone(ZoneId.systemDefault()).toOffsetDateTime();
            default -> OffsetDateTime.from(value);
        };
    }

    private static String title(VEvent event) {
        return value(event, "SUMMARY").orElse("");
    }

    private static String description(VEvent event) {
        return value(event, "DESCRIPTION").orElse(null);
    }

    private static String location(VEvent event) {
        return value(event, "LOCATION").orElse(null);
    }

    private static Optional<String> value(VEvent event, String name) {
        return event.getProperty(name).map(property -> ((net.fortuna.ical4j.model.Property) property).getValue());
    }
}
