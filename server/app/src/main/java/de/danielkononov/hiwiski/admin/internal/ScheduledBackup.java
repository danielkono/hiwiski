package de.danielkononov.hiwiski.admin.internal;

import java.time.Instant;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * The scheduled backup.
 *
 * <p>Not a cron expression: the schedule is a setting the family changes in the app, and
 * a change applies at once, without a restart. And a NAS asleep at two in the night is
 * common -- checked at start and every few minutes after, a missed run is caught up as
 * soon as the server is awake.
 */
@Component
class ScheduledBackup {

    private final BackupService backups;

    ScheduledBackup(BackupService backups) {
        this.backups = backups;
    }

    @Scheduled(
            initialDelayString = "${hiwiski.backup-check-interval:PT1M}",
            fixedDelayString = "${hiwiski.backup-check-interval:PT5M}")
    public void run() {
        backups.createIfDue(Instant.now());
    }
}
