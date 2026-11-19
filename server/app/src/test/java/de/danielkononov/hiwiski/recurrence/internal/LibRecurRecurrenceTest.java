package de.danielkononov.hiwiski.recurrence.internal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;

/** An old high-frequency rule expands for its window, not from its first occurrence. */
class LibRecurRecurrenceTest {

    @Test
    void aMinutelyRuleFromYearsAgoExpandsQuickly() {
        var started = Instant.now();
        var occurrences = new LibRecurRecurrence()
                .expand(
                        "FREQ=MINUTELY",
                        LocalDateTime.of(2015, 1, 1, 0, 0),
                        "Europe/Berlin",
                        LocalDateTime.of(2026, 10, 8, 10, 0),
                        LocalDateTime.of(2026, 10, 8, 10, 5));

        assertThat(occurrences).hasSize(5);
        assertThat(occurrences.getFirst()).isEqualTo(LocalDateTime.of(2026, 10, 8, 10, 0));
        assertThat(Duration.between(started, Instant.now())).isLessThan(Duration.ofSeconds(2));
    }

    @Test
    void aWeeklyRuleStillStartsOnItsOwnDay() {
        var occurrences = new LibRecurRecurrence()
                .expand(
                        "FREQ=WEEKLY",
                        LocalDateTime.of(2020, 1, 6, 8, 0),
                        "Europe/Berlin",
                        LocalDateTime.of(2026, 10, 1, 0, 0),
                        LocalDateTime.of(2026, 10, 15, 0, 0));

        assertThat(occurrences)
                .containsExactly(LocalDateTime.of(2026, 10, 5, 8, 0), LocalDateTime.of(2026, 10, 12, 8, 0));
    }
}
