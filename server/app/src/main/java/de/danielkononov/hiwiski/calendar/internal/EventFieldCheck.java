package de.danielkononov.hiwiski.calendar.internal;

import de.danielkononov.hiwiski.recurrence.Recurrence;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeParseException;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * The fields of an event that go into an ICS feed <em>as they are</em>, checked on the
 * way in.
 *
 * <p>Title, description and location are TEXT and escaped when written. The rule, the
 * zone, the local times and the exception keys are not TEXT: they stood in the file
 * verbatim, and a member with WRITE on a shared calendar could start content lines of
 * their own in every subscriber's calendar — forged events, overridden UIDs, alarms,
 * even in a busy-only feed. Each is now only what
 * it claims to be: a rule the library reads, an IANA zone, a local date-time.
 */
final class EventFieldCheck {

    /** What a rule is made of. A colon or a line break is never part of one. */
    private static final Pattern RULE_CHARACTERS = Pattern.compile("(?:RRULE:)?[A-Za-z0-9=;,+\\-]{1,500}");

    /**
     * A local date, or date-time, with a four-digit year. {@code LocalDate.parse} also
     * reads {@code +10000-01-01} and {@code -0001-01-01}; the feed then failed on such a
     * key for every subscriber.
     */
    private static final Pattern LOCAL_SHAPE =
            Pattern.compile("\\d{4}-\\d{2}-\\d{2}(?:T\\d{2}:\\d{2}(?::\\d{2}(?:\\.\\d{1,9})?)?)?");

    private EventFieldCheck() {}

    /** Whether the fields of a mutation may be stored. Fields left out are not looked at. */
    static boolean acceptable(Map<String, Object> fields, Recurrence recurrence) {
        if (fields == null) {
            return true;
        }
        return rule(fields.get("rrule"), recurrence)
                && optional(fields, "timeZone", EventFieldCheck::zone)
                && optional(fields, "localStart", EventFieldCheck::localDateTime)
                && optional(fields, "localEnd", EventFieldCheck::localDateTime)
                && exceptions(fields.get("exceptions"));
    }

    /**
     * Whether a new event has the times of its form, and whether the times a mutation
     * brings together stand in order. An event without a start was stored and shown
     * nowhere; one that ends before it starts drew backwards in the week view.
     *
     * <p>Only what the mutation itself says: a change of the end alone is not compared
     * with a start it does not carry.
     */
    static boolean timed(Map<String, Object> fields, boolean exists) {
        if (fields == null) {
            return true;
        }
        if (!exists) {
            // A form this server does not know is a newer app's, and not judged here.
            String start = switch (String.valueOf(fields.get("timeForm"))) {
                case EventOccurrences.TIMED -> "startsAt";
                case EventOccurrences.ALL_DAY -> "startDate";
                case EventOccurrences.RECURRING -> "localStart";
                default -> null;
            };
            if (start != null && fields.get(start) == null) {
                return false;
            }
        }
        return inOrder(fields, "startsAt", "endsAt")
                && inOrder(fields, "startDate", "endDate")
                && inOrder(fields, "localStart", "localEnd");
    }

    /**
     * Compared as text where both are written the same way: dates and local date-times
     * sort as they read. Instants carry an offset and are parsed.
     */
    private static boolean inOrder(Map<String, Object> fields, String start, String end) {
        if (!(fields.get(start) instanceof String from) || !(fields.get(end) instanceof String to)) {
            return true;
        }
        if (!"startsAt".equals(start)) {
            return from.length() != to.length() || from.compareTo(to) <= 0;
        }
        try {
            return !java.time.OffsetDateTime.parse(to).isBefore(java.time.OffsetDateTime.parse(from));
        } catch (DateTimeParseException e) {
            // Not this check's to refuse: the field's own decoder does.
            return true;
        }
    }

    private static boolean optional(Map<String, Object> fields, String name, java.util.function.Predicate<String> check) {
        Object value = fields.get(name);
        return value == null || value instanceof String text && check.test(text);
    }

    private static boolean rule(Object value, Recurrence recurrence) {
        if (value == null) {
            return true;
        }
        if (!(value instanceof String rule)) {
            return false;
        }
        // An empty rule is how a device ends a series.
        return rule.isBlank() || RULE_CHARACTERS.matcher(rule).matches() && recurrence.accepts(rule);
    }

    private static boolean zone(String id) {
        return ZoneId.getAvailableZoneIds().contains(id);
    }

    /** {@code 2026-10-19T12:00}, with or without seconds -- as the devices write it. */
    private static boolean localDateTime(String value) {
        if (value.indexOf('T') < 0 || !localShape(value)) {
            return false;
        }
        try {
            LocalDateTime.parse(value);
            return true;
        } catch (DateTimeParseException e) {
            return false;
        }
    }

    /**
     * The exceptions: keyed by the original start, each a moved occurrence with
     * {@code start} and {@code end} or a cancelled one. A {@code null} entry takes one
     * back.
     */
    private static boolean exceptions(Object value) {
        if (value == null) {
            return true;
        }
        if (!(value instanceof Map<?, ?> exceptions)) {
            return false;
        }
        for (var exception : exceptions.entrySet()) {
            if (!(exception.getKey() instanceof String key) || !dateOrDateTime(key)) {
                return false;
            }
            Object entry = exception.getValue();
            if (entry == null) {
                continue;
            }
            if (!(entry instanceof Map<?, ?> fields)) {
                return false;
            }
            for (String name : new String[] {"start", "end"}) {
                Object time = fields.get(name);
                if (time != null && !(time instanceof String text && dateOrDateTime(text))) {
                    return false;
                }
            }
            Object cancelled = fields.get("cancelled");
            if (cancelled != null && !(cancelled instanceof Boolean)) {
                return false;
            }
        }
        return true;
    }

    private static boolean dateOrDateTime(String value) {
        if (localDateTime(value)) {
            return true;
        }
        if (value.indexOf('T') >= 0 || !localShape(value)) {
            return false;
        }
        try {
            LocalDate.parse(value);
            return true;
        } catch (DateTimeParseException e) {
            return false;
        }
    }

    /** Years 0001 to 9999, written with four digits: what RFC 5545 can carry. */
    private static boolean localShape(String value) {
        return LOCAL_SHAPE.matcher(value).matches() && !value.startsWith("0000");
    }
}
