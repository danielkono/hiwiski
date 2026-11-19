package de.danielkononov.hiwiski.calendar.internal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;

/**
 * A subscription is due once its interval is up -- measured from when the last fetch
 * finished, a few seconds after the run that started it.
 */
class SubscriptionDueTest {

    private static final OffsetDateTime RUN = OffsetDateTime.of(2026, 10, 8, 11, 15, 0, 0, ZoneOffset.UTC);

    @Test
    void anHourlySubscriptionIsDueOnTheNextHourlyRun() {
        // The fetch of the 10:15 run finished at 10:15:04.
        assertThat(SubscriptionService.isDue("HOURLY", RUN.minusMinutes(59).minusSeconds(56), RUN))
                .isTrue();
    }

    @Test
    void aDailySubscriptionIsDueTheNextDay() {
        assertThat(SubscriptionService.isDue("DAILY", RUN.minusDays(1).plusSeconds(4), RUN))
                .isTrue();
    }

    @Test
    void halfAnIntervalIsNotDue() {
        assertThat(SubscriptionService.isDue("HOURLY", RUN.minusMinutes(30), RUN)).isFalse();
        assertThat(SubscriptionService.isDue("WEEKLY", RUN.minusDays(6), RUN)).isFalse();
    }
}
