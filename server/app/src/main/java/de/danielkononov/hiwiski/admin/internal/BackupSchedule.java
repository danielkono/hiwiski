package de.danielkononov.hiwiski.admin.internal;

import de.danielkononov.hiwiski.platform.InstanceSettings;
import de.danielkononov.hiwiski.platform.SettingKey;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.format.DateTimeParseException;
import java.time.temporal.TemporalAdjusters;

/**
 * When the scheduled backup runs: daily, or weekly on one weekday, at a time in the
 * family's time zone. There is no "off".
 */
record BackupSchedule(Frequency frequency, DayOfWeek weekday, LocalTime time, ZoneId zone, int keep) {

    enum Frequency {
        DAILY,
        WEEKLY
    }

    static final int KEEP_DEFAULT = 7;
    static final int KEEP_MAX = 30;
    static final LocalTime TIME_DEFAULT = LocalTime.of(2, 0);

    /** From the settings; a value that cannot be read is its default. */
    static BackupSchedule of(InstanceSettings settings) {
        Frequency frequency;
        try {
            frequency = Frequency.valueOf(settings.get(SettingKey.BACKUP_FREQUENCY, Frequency.DAILY.name()));
        } catch (IllegalArgumentException e) {
            frequency = Frequency.DAILY;
        }
        int weekday = settings.getInt(SettingKey.BACKUP_WEEKDAY, 1);
        LocalTime time;
        try {
            time = LocalTime.parse(settings.get(SettingKey.BACKUP_TIME, "02:00"));
        } catch (DateTimeParseException e) {
            time = TIME_DEFAULT;
        }
        ZoneId zone;
        try {
            zone = ZoneId.of(settings.get(SettingKey.FAMILY_TIMEZONE, "UTC"));
        } catch (RuntimeException e) {
            zone = ZoneId.of("UTC");
        }
        return new BackupSchedule(
                frequency,
                DayOfWeek.of(Math.clamp(weekday, 1, 7)),
                time,
                zone,
                Math.clamp(settings.getInt(SettingKey.BACKUP_KEEP, KEEP_DEFAULT), 1, KEEP_MAX));
    }

    /** The last time the schedule named, at or before {@code now}. */
    Instant lastDue(Instant now) {
        ZonedDateTime local = now.atZone(zone);
        ZonedDateTime candidate = local.with(time).withSecond(0).withNano(0);
        if (frequency == Frequency.WEEKLY) {
            candidate = candidate.with(TemporalAdjusters.previousOrSame(weekday));
            if (candidate.isAfter(local)) {
                candidate = candidate.minusWeeks(1);
            }
        } else if (candidate.isAfter(local)) {
            candidate = candidate.minusDays(1);
        }
        return candidate.toInstant();
    }

    /** The next time the schedule names, after {@code now}. */
    Instant nextDue(Instant now) {
        ZonedDateTime last = lastDue(now).atZone(zone);
        return (frequency == Frequency.WEEKLY ? last.plusWeeks(1) : last.plusDays(1))
                .with(time)
                .toInstant();
    }

    /**
     * Whether a backup is due: none has been made since the last time the schedule
     * named. A NAS asleep at two in the night catches up when it wakes.
     */
    boolean due(Instant now, Instant newestBackup) {
        return newestBackup == null || newestBackup.isBefore(lastDue(now));
    }
}
