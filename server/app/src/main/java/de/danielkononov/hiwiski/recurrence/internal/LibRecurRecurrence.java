package de.danielkononov.hiwiski.recurrence.internal;

import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.recurrence.Recurrence;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TimeZone;
import org.dmfs.rfc5545.DateTime;
import org.dmfs.rfc5545.recur.Freq;
import org.dmfs.rfc5545.recur.InvalidRecurrenceRuleException;
import org.dmfs.rfc5545.recur.RecurrenceRule;
import org.springframework.stereotype.Service;

/**
 * The expansion with {@code lib-recur}.
 *
 * <p>The library calculates on {@link DateTime} with a zone. The series is therefore
 * expanded in its own zone and only then read back as local time — that way "every
 * Monday 8:00" stays 8:00 across a clock change.
 */
@Service
class LibRecurRecurrence implements Recurrence {

    /** How many occurrences one expansion may step through at most. */
    private static final int MAX_STEPS = 100_000;

    @Override
    public List<LocalDateTime> expand(
            String rrule, LocalDateTime start, String timeZone, LocalDateTime from, LocalDateTime to) {

        if (rrule == null || rrule.isBlank()) {
            // No rule means: exactly once, on the start date.
            return (!start.isBefore(from) && start.isBefore(to)) ? List.of(start) : List.of();
        }

        ZoneId zone = zone(timeZone);
        TimeZone legacy = TimeZone.getTimeZone(zone);

        RecurrenceRule rule;
        try {
            rule = new RecurrenceRule(rrule.replaceFirst("^RRULE:", ""), RecurrenceRule.RfcMode.RFC5545_LAX);
        } catch (InvalidRecurrenceRuleException e) {
            throw HiwiskiException.invalid("calendar.rrule_invalid", "rrule", rrule);
        }

        DateTime seed = new DateTime(
                legacy,
                start.getYear(),
                start.getMonthValue() - 1,
                start.getDayOfMonth(),
                start.getHour(),
                start.getMinute(),
                start.getSecond());

        List<LocalDateTime> result = new ArrayList<>();
        var iterator = rule.iterator(seed);

        // Fast-forward to the window: the view only ever asks for a slice and must not
        // have to start at the first occurrence. Stepping there one by one cost millions
        // of iterations for a minutely rule started years ago -- per request.
        LocalDateTime windowStart = from.minusDays(1);
        if (windowStart.isAfter(start)) {
            iterator.fastForward(new DateTime(
                    legacy,
                    windowStart.getYear(),
                    windowStart.getMonthValue() - 1,
                    windowStart.getDayOfMonth(),
                    windowStart.getHour(),
                    windowStart.getMinute(),
                    windowStart.getSecond()));
        }
        // And a ceiling on the steps either way: a rule whose occurrences mostly fall
        // outside the window must not keep a request thread busy.
        int steps = 0;
        while (iterator.hasNext() && result.size() < MAX_OCCURRENCES && steps++ < MAX_STEPS) {
            DateTime next = iterator.nextDateTime();
            LocalDateTime local = toLocal(next, zone);
            if (local.isBefore(from)) {
                continue;
            }
            if (!local.isBefore(to)) {
                break;
            }
            result.add(local);
        }
        return result;
    }

    /**
     * Back to local time.
     *
     * <p>Via the instant and the zone, not via the raw fields: for a rule in a foreign
     * zone the library delivers an instant, and only the zone turns it back into "8:00".
     */
    private static LocalDateTime toLocal(DateTime value, ZoneId zone) {
        return java.time.Instant.ofEpochMilli(value.getTimestamp()).atZone(zone).toLocalDateTime();
    }

    @Override
    public boolean accepts(String rrule) {
        if (rrule == null || rrule.isBlank()) {
            return false;
        }
        try {
            String text = rrule.trim().replaceFirst("^RRULE:", "");
            RecurrenceRule rule = new RecurrenceRule(text, RecurrenceRule.RfcMode.RFC5545_LAX);
            return expandable(statedFreq(text, rule.getFreq()), parts(text)) && expandsInTrial(rule);
        } catch (InvalidRecurrenceRuleException | RuntimeException e) {
            return false;
        }
    }

    /**
     * Rules whose parts the devices' library searches through one candidate at a time,
     * without ever yielding: {@code FREQ=MINUTELY;BYSETPOS=2;BYMINUTE=0} or
     * {@code FREQ=HOURLY;BYWEEKNO=53;BYMONTH=6} froze every reader's calendar for more
     * than a minute per expansion.
     *
     * <ul>
     *   <li>No {@code SECONDLY}: the devices' library cannot step it.
     *   <li>{@code BYWEEKNO} and {@code BYYEARDAY} only with {@code YEARLY};
     *       {@code BYSETPOS} only with {@code WEEKLY}, {@code MONTHLY} or {@code YEARLY};
     *       a numbered {@code BYDAY} ({@code 2TU}) only with {@code MONTHLY} or
     *       {@code YEARLY}. RFC 5545 forbids most of the rest, and no family calendar
     *       needs it: below those frequencies the devices search every hour or day up to
     *       the year 9999 for a set that never comes.
     *   <li>With {@code BYHOUR} ({@code HOURLY}) or {@code BYHOUR}/{@code BYMINUTE}
     *       ({@code MINUTELY}), only an interval that reaches every hour of the day
     *       (no common divisor with 24) or every minute of the hour (below 60, none
     *       with 60): the devices' library steps by the interval until the hour or
     *       minute matches, and {@code FREQ=HOURLY;INTERVAL=24;BYHOUR=5} from a start at
     *       4:00 never does -- 13 s, until the date overflowed.
     *   <li>An {@code INTERVAL} only as a whole number from 1 on: with 0 the devices'
     *       library never moves on from its first period --
     *       {@code FREQ=WEEKLY;INTERVAL=0;BYDAY=MO} did not return at all.
     * </ul>
     *
     * <p>The parts are read from the text: in lenient mode the library drops or changes
     * some it does not allow ({@code BYWEEKNO} with {@code MONTHLY}), the devices'
     * library does not -- and the text is what they expand. The app applies the same
     * list ({@code golden/recurrence-limits.json}).
     */
    private static boolean expandable(Freq freq, Map<String, String> parts) {
        if (freq == Freq.SECONDLY) {
            return false;
        }
        if (parts.containsKey("INTERVAL") && !POSITIVE_NUMBER.matcher(parts.get("INTERVAL").trim()).matches()) {
            return false;
        }
        boolean yearly = freq == Freq.YEARLY;
        boolean monthlyOrYearly = yearly || freq == Freq.MONTHLY;
        if ((parts.containsKey("BYWEEKNO") || parts.containsKey("BYYEARDAY")) && !yearly) {
            return false;
        }
        if (parts.containsKey("BYSETPOS") && !(monthlyOrYearly || freq == Freq.WEEKLY)) {
            return false;
        }
        if (!monthlyOrYearly && NUMBERED_DAY.matcher(parts.getOrDefault("BYDAY", "")).find()) {
            return false;
        }
        long interval = interval(parts.get("INTERVAL"));
        if (freq == Freq.HOURLY && parts.containsKey("BYHOUR") && gcd(interval, 24) != 1) {
            return false;
        }
        return !(freq == Freq.MINUTELY
                && (parts.containsKey("BYHOUR") || parts.containsKey("BYMINUTE"))
                && (interval >= 60 || gcd(interval, 60) != 1));
    }

    private static long interval(String value) {
        try {
            return value == null || value.isBlank() ? 1 : Long.parseLong(value.trim());
        } catch (NumberFormatException e) {
            return 1;
        }
    }

    private static long gcd(long a, long b) {
        return b == 0 ? Math.abs(a) : gcd(b, a % b);
    }

    /** A {@code BYDAY} entry with a number in front: {@code 2TU}, {@code -1FR}. */
    private static final java.util.regex.Pattern NUMBERED_DAY = java.util.regex.Pattern.compile("[0-9]");

    /** A whole number from 1 on, short enough to be one. */
    private static final java.util.regex.Pattern POSITIVE_NUMBER =
            java.util.regex.Pattern.compile("0*[1-9][0-9]{0,8}");

    /** The frequency the text states: in lenient mode the library may change it. */
    private static Freq statedFreq(String text, Freq parsed) {
        for (String part : text.split(";")) {
            int equals = part.indexOf('=');
            if (equals > 0 && part.substring(0, equals).trim().equalsIgnoreCase("FREQ")) {
                try {
                    return Freq.valueOf(part.substring(equals + 1).trim().toUpperCase(java.util.Locale.ROOT));
                } catch (IllegalArgumentException unknown) {
                    return parsed;
                }
            }
        }
        return parsed;
    }

    /** The parts a rule's text has, by their names in upper case. */
    private static Map<String, String> parts(String text) {
        var parts = new java.util.HashMap<String, String>();
        for (String part : text.split(";")) {
            int equals = part.indexOf('=');
            String name = (equals < 0 ? part : part.substring(0, equals)).trim().toUpperCase(java.util.Locale.ROOT);
            parts.put(name, equals < 0 ? "" : part.substring(equals + 1));
        }
        return parts;
    }

    /** How many occurrences the trial expands at most. */
    private static final int TRIAL_OCCURRENCES = 500;

    /**
     * Whether the library itself gets through the first occurrences. It gives up with
     * "too many empty recurrence sets" on every rule above that searches long without
     * finding one -- and on any other such rule the list above does not name.
     */
    private static boolean expandsInTrial(RecurrenceRule rule) {
        var iterator = rule.iterator(new DateTime(TimeZone.getTimeZone("UTC"), 2024, 0, 1, 0, 0, 0));
        for (int i = 0; i < TRIAL_OCCURRENCES && iterator.hasNext(); i++) {
            iterator.nextDateTime();
        }
        return true;
    }

    private static ZoneId zone(String timeZone) {
        try {
            return timeZone == null || timeZone.isBlank() ? ZoneId.systemDefault() : ZoneId.of(timeZone);
        } catch (RuntimeException e) {
            throw HiwiskiException.invalid("calendar.timezone_invalid", "timeZone", String.valueOf(timeZone));
        }
    }
}
