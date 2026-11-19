package de.danielkononov.hiwiski.admin.internal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneId;
import org.junit.jupiter.api.Test;

class BackupScheduleTest {

    private static final ZoneId BERLIN = ZoneId.of("Europe/Berlin");

    private static final BackupSchedule DAILY = new BackupSchedule(
            BackupSchedule.Frequency.DAILY, DayOfWeek.MONDAY, LocalTime.of(2, 0), BERLIN, 7);

    @Test
    void dailyAtTwoInTheFamilysZone() {
        // 2026-11-04 10:00 in Berlin is 09:00 UTC.
        Instant now = Instant.parse("2026-11-04T09:00:00Z");

        assertThat(DAILY.lastDue(now)).isEqualTo(Instant.parse("2026-11-04T01:00:00Z"));
        assertThat(DAILY.nextDue(now)).isEqualTo(Instant.parse("2026-11-05T01:00:00Z"));
    }

    @Test
    void beforeTwoTheLastRunWasYesterday() {
        Instant now = Instant.parse("2026-11-04T00:30:00Z");

        assertThat(DAILY.lastDue(now)).isEqualTo(Instant.parse("2026-11-03T01:00:00Z"));
    }

    /** A NAS asleep at two in the night backs up when it wakes -- once. */
    @Test
    void aMissedRunIsCaughtUpOnce() {
        Instant woke = Instant.parse("2026-11-04T07:00:00Z");

        assertThat(DAILY.due(woke, Instant.parse("2026-11-03T01:00:30Z"))).isTrue();
        assertThat(DAILY.due(woke, Instant.parse("2026-11-04T07:00:10Z"))).isFalse();
        assertThat(DAILY.due(woke, null)).isTrue();
    }

    @Test
    void weeklyOnItsWeekday() {
        var weekly = new BackupSchedule(
                BackupSchedule.Frequency.WEEKLY, DayOfWeek.SUNDAY, LocalTime.of(3, 30), BERLIN, 7);
        // Wednesday 2026-11-04.
        Instant now = Instant.parse("2026-11-04T09:00:00Z");

        assertThat(weekly.lastDue(now)).isEqualTo(Instant.parse("2026-11-01T02:30:00Z"));
        assertThat(weekly.nextDue(now)).isEqualTo(Instant.parse("2026-11-08T02:30:00Z"));
    }

    /** The night the clocks change still has its two o'clock -- the second one, in winter time. */
    @Test
    void acrossTheChangeOfTime() {
        // 2026-10-25: 03:00 summer time becomes 02:00 winter time in Berlin.
        Instant now = Instant.parse("2026-10-25T12:00:00Z");

        assertThat(DAILY.lastDue(now)).isEqualTo(Instant.parse("2026-10-25T01:00:00Z"));
        assertThat(DAILY.nextDue(now)).isEqualTo(Instant.parse("2026-10-26T01:00:00Z"));
    }
}
