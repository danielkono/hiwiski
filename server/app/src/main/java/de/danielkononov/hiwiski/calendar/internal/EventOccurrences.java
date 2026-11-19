package de.danielkononov.hiwiski.calendar.internal;

import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.recurrence.Recurrence;
import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.UnaryOperator;

/**
 * Expands an event into the occurrences of a window — the server's reading of the app's
 * {@code EventExpander} ({@code app/lib/domain/calendar/occurrence.dart}).
 *
 * <p>Only the home screen widget's agenda needs it: everywhere else the app expands
 * events itself, from its own database, so that the calendar works offline. The widget
 * asks the server while the app is closed, and it must show what the calendar shows.
 * Two readings of the same rule that differ are worse than one, so both are checked
 * against {@code golden/occurrences.json}; a change here belongs there first.
 *
 * <p>Three time forms, three paths, as in the app: {@code TIMED} is a point in time,
 * read in the viewer's zone; {@code ALL_DAY} is dates; {@code RECURRING} hangs on the
 * wall clock of its own zone and is shown at that time. Exceptions are keyed by the
 * original start of their occurrence, in local time to the minute — a cancellation
 * ({@code cancelled}) or a move ({@code start}, {@code end}).
 *
 * <p>The window is half-open, {@code [from, to)}, in local time. The edges differ by
 * form exactly as in the app — an event that ends at {@code from} still counts, an
 * all-day event counts through the whole of its last day.
 */
final class EventOccurrences {

    static final String TIMED = "TIMED";
    static final String ALL_DAY = "ALL_DAY";
    static final String RECURRING = "RECURRING";

    private static final String CANCELLED = "cancelled";
    private static final String START = "start";
    private static final String END = "end";
    private static final String UTC = "UTC";

    /** The key of an exception: the original start, to the minute. */
    private static final DateTimeFormatter KEY = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm");

    /** What an event's time is made of, as stored. */
    record Times(
            String timeForm,
            OffsetDateTime startsAt,
            OffsetDateTime endsAt,
            LocalDate startDate,
            LocalDate endDate,
            String localStart,
            String localEnd,
            String timeZone,
            String rrule,
            Map<String, Object> exceptions) {}

    /**
     * One occurrence, in local time. For an all-day one the days at midnight, the end day
     * inclusive.
     */
    record Occurrence(LocalDateTime start, LocalDateTime end, boolean allDay, boolean moved) {}

    /** The app's order within a day: all-day ones first, they frame the day. */
    static final Comparator<Occurrence> ORDER = Comparator.<Occurrence, LocalDate>comparing(
                    occurrence -> occurrence.start().toLocalDate())
            .thenComparing(occurrence -> !occurrence.allDay())
            .thenComparing(Occurrence::start);

    private final Recurrence recurrence;

    EventOccurrences(Recurrence recurrence) {
        this.recurrence = recurrence;
    }

    /**
     * @param viewer the zone a {@code TIMED} event's instants are read in
     */
    List<Occurrence> expand(Times event, LocalDateTime from, LocalDateTime to, ZoneId viewer) {
        List<Occurrence> result = switch (event.timeForm() == null ? TIMED : event.timeForm()) {
            case ALL_DAY -> allDay(event, from, to);
            case RECURRING -> recurring(event, from, to);
            default -> timed(event, from, to, viewer);
        };
        return result.stream().sorted(ORDER).toList();
    }

    private static List<Occurrence> timed(Times event, LocalDateTime from, LocalDateTime to, ZoneId viewer) {
        if (event.startsAt() == null) {
            return List.of();
        }
        LocalDateTime start = event.startsAt().atZoneSameInstant(viewer).toLocalDateTime();
        LocalDateTime end = event.endsAt() == null
                ? start
                : event.endsAt().atZoneSameInstant(viewer).toLocalDateTime();
        if (end.isBefore(from) || !start.isBefore(to)) {
            return List.of();
        }
        return List.of(new Occurrence(start, end, false, false));
    }

    private List<Occurrence> allDay(Times event, LocalDateTime from, LocalDateTime to) {
        LocalDate start = event.startDate();
        if (start == null) {
            return List.of();
        }
        LocalDate end = event.endDate() == null ? start : event.endDate();
        if (event.rrule() != null && !event.rrule().isBlank()) {
            return allDaySeries(event, start, end, from, to);
        }
        // The whole end day still counts.
        if (end.atTime(23, 59, 59).isBefore(from) || !start.atStartOfDay().isBefore(to)) {
            return List.of();
        }
        return List.of(new Occurrence(start.atStartOfDay(), end.atStartOfDay(), true, false));
    }

    /**
     * A series of whole days — a birthday, a yearly holiday — expanded over dates, each
     * occurrence as long as the first.
     */
    private List<Occurrence> allDaySeries(
            Times event, LocalDate start, LocalDate end, LocalDateTime from, LocalDateTime to) {
        LocalDateTime first = start.atStartOfDay();
        long days = ChronoUnit.DAYS.between(start, end);
        Map<String, Object> exceptions = exceptions(event);
        String zone = zone(event);

        // The look-behind of a multi-day series: one that began before the window may
        // still run into it.
        List<LocalDateTime> starts = expand(
                event.rrule(), first, zone, from.toLocalDate().atStartOfDay().minusDays(days), to);

        List<Occurrence> result = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (LocalDateTime day : starts) {
            String key = KEY.format(day);
            seen.add(key);
            Object exception = exceptions.get(key);
            if (cancelled(exception)) {
                continue;
            }
            LocalDateTime actualStart = day;
            LocalDateTime actualEnd = day.plusDays(days);
            boolean moved = false;
            if (exception instanceof Map<?, ?> change) {
                LocalDateTime movedStart = parseLocal(change.get(START));
                if (movedStart != null) {
                    actualStart = movedStart.toLocalDate().atStartOfDay();
                    LocalDateTime movedEnd = parseLocal(change.get(END));
                    actualEnd = movedEnd == null
                            ? actualStart.plusDays(days)
                            : movedEnd.toLocalDate().atStartOfDay();
                    moved = true;
                }
            }
            if (!actualEnd.plusDays(1).isAfter(from) || !actualStart.isBefore(to)) {
                continue;
            }
            result.add(new Occurrence(actualStart, actualEnd, true, moved));
        }
        result.addAll(movedIn(event, exceptions, seen, from, to, first, zone, value -> value.plusDays(days), true));
        return result;
    }

    private List<Occurrence> recurring(Times event, LocalDateTime from, LocalDateTime to) {
        LocalDateTime seed = parseLocal(event.localStart());
        if (seed == null) {
            return List.of();
        }
        LocalDateTime localEnd = parseLocal(event.localEnd());
        // The length on the wall clock: Friday 18:00 to Sunday 12:00 stays that, even
        // over the night the clocks change.
        Duration duration = localEnd == null ? Duration.ZERO : Duration.between(seed, localEnd);
        String zone = zone(event);
        Map<String, Object> exceptions = exceptions(event);

        // A window with a look-behind: an occurrence that starts before the window and
        // reaches into it belongs in it.
        Duration lookBehind = duration.isPositive() ? duration : Duration.ZERO;
        List<LocalDateTime> starts = expand(event.rrule(), seed, zone, from.minus(lookBehind), to);

        List<Occurrence> result = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (LocalDateTime start : starts) {
            String key = KEY.format(start);
            seen.add(key);
            Object exception = exceptions.get(key);
            if (cancelled(exception)) {
                continue;
            }
            LocalDateTime actualStart = start;
            LocalDateTime actualEnd = start.plus(duration);
            boolean moved = false;
            if (exception instanceof Map<?, ?> change) {
                LocalDateTime movedStart = parseLocal(change.get(START));
                if (movedStart != null) {
                    actualStart = movedStart;
                    LocalDateTime movedEnd = parseLocal(change.get(END));
                    actualEnd = movedEnd == null ? movedStart.plus(duration) : movedEnd;
                    moved = true;
                }
            }
            if (actualEnd.isBefore(from) || !actualStart.isBefore(to)) {
                continue;
            }
            result.add(new Occurrence(actualStart, actualEnd, false, moved));
        }
        result.addAll(movedIn(event, exceptions, seen, from, to, seed, zone, value -> value.plus(duration), false));
        return result;
    }

    /**
     * The occurrences moved <strong>into</strong> the window from an original start
     * outside it — Monday's lesson moved to the Friday before. The expansion only reaches
     * the original starts inside the window, so these would be missing.
     *
     * <p>Only a key that is a real occurrence of the rule counts; one left behind by a
     * changed rule does not.
     */
    private List<Occurrence> movedIn(
            Times event,
            Map<String, Object> exceptions,
            Set<String> seen,
            LocalDateTime from,
            LocalDateTime to,
            LocalDateTime seed,
            String zone,
            UnaryOperator<LocalDateTime> length,
            boolean allDay) {
        List<Occurrence> result = new ArrayList<>();
        for (var entry : exceptions.entrySet()) {
            if (seen.contains(entry.getKey()) || !(entry.getValue() instanceof Map<?, ?> change)) {
                continue;
            }
            if (cancelled(change)) {
                continue;
            }
            LocalDateTime original = parseLocal(entry.getKey());
            LocalDateTime start = parseLocal(change.get(START));
            if (original == null || start == null) {
                continue;
            }
            LocalDateTime end = parseLocal(change.get(END));
            if (end == null) {
                end = length.apply(start);
            }
            if (allDay) {
                start = start.toLocalDate().atStartOfDay();
                end = end.toLocalDate().atStartOfDay();
            }
            boolean over = allDay ? !end.plusDays(1).isAfter(from) : end.isBefore(from);
            if (over || !start.isBefore(to)) {
                continue;
            }
            if (!expand(event.rrule(), seed, zone, original, original.plusSeconds(1)).contains(original)) {
                continue;
            }
            result.add(new Occurrence(start, end, allDay, true));
        }
        return result;
    }

    /**
     * The rule's starts — or, for a rule that cannot be expanded, the event once on its
     * start, as the app shows it: a rule from a subscribed feed that neither side reads
     * must not cost the agenda its other events.
     */
    private List<LocalDateTime> expand(
            String rrule, LocalDateTime start, String zone, LocalDateTime from, LocalDateTime to) {
        if (rrule != null && !rrule.isBlank() && recurrence.accepts(rrule)) {
            try {
                return recurrence.expand(rrule, start, zone, from, to);
            } catch (HiwiskiException unreadable) {
                // Shown once, below.
            }
        }
        return !start.isBefore(from) && start.isBefore(to) ? List.of(start) : List.of();
    }

    private static boolean cancelled(Object exception) {
        return exception instanceof Map<?, ?> change && Boolean.TRUE.equals(change.get(CANCELLED));
    }

    private static Map<String, Object> exceptions(Times event) {
        return event.exceptions() == null ? Map.of() : event.exceptions();
    }

    private static String zone(Times event) {
        return event.timeZone() == null || event.timeZone().isBlank() ? UTC : event.timeZone();
    }

    /**
     * A local time as the app reads one ({@code DateTime.tryParse}): to the minute or the
     * second, or a bare date at midnight. {@code null} for anything else — a broken
     * exception must not cost the calendar.
     */
    static LocalDateTime parseLocal(Object raw) {
        if (!(raw instanceof String text) || text.isBlank()) {
            return null;
        }
        String value = text.trim().replace(' ', 'T');
        try {
            return LocalDateTime.parse(value);
        } catch (DateTimeParseException notLocal) {
            // A date, or a time with an offset, below.
        }
        try {
            return LocalDate.parse(value).atStartOfDay();
        } catch (DateTimeParseException notADate) {
            // An offset, below.
        }
        try {
            return OffsetDateTime.parse(value).toLocalDateTime();
        } catch (DateTimeParseException unreadable) {
            return null;
        }
    }
}
