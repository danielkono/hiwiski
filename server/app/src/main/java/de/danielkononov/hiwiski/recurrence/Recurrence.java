package de.danielkononov.hiwiski.recurrence;

import java.time.LocalDateTime;
import java.util.List;

/**
 * Expands a recurrence rule.
 *
 * <p>Calculation happens in <strong>local time</strong>. "Every Monday 8:00" stays 8:00,
 * even across a clock change; calculated in UTC it would shift to 9:00 — that is exactly
 * why the {@code RECURRING} time form has its own fields with {@code local_start} and
 * {@code time_zone}.
 *
 * <p>It is tested against {@code golden/recurrence.json} — the same file the client
 * tests against. Two libraries that behave differently in edge cases are not two
 * opinions that can be left standing side by side.
 */
public interface Recurrence {

    /**
     * All occurrences in the half-open window {@code [from, to)}.
     *
     * @param rrule the rule without the {@code RRULE:} prefix
     * @param start the first event of the series, in local time
     * @param timeZone the zone the series is meant in
     */
    List<LocalDateTime> expand(
            String rrule, LocalDateTime start, String timeZone, LocalDateTime from, LocalDateTime to);

    /**
     * Whether a rule may be stored: one this library reads, that every device can expand.
     *
     * <p>{@code FREQ=SECONDLY} is refused: the devices' library cannot step it, and no
     * family calendar needs it. The rule arrives through sync as plain text and goes
     * into every subscriber's feed, so it is checked before it is stored.
     *
     * @param rrule the rule, with or without the {@code RRULE:} prefix
     */
    boolean accepts(String rrule);

    /**
     * The maximum number of occurrences delivered.
     *
     * <p>A rule without {@code COUNT} and without {@code UNTIL} is infinite; the window
     * limits it, but a very large window must not keep the server busy.
     */
    int MAX_OCCURRENCES = 2000;
}
