package de.danielkononov.hiwiski.sync.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.PROCESSED_MUTATION;

import de.danielkononov.hiwiski.platform.InstanceSettings;
import de.danielkononov.hiwiski.platform.SettingKey;
import java.time.OffsetDateTime;
import org.jooq.DSLContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Daily: clean up the log and the mutation idempotency records.
 *
 * <p>Both with the same retention period, because a retry without its log entry could no
 * longer answer anything.
 *
 * <p>The period also limits how far back the <strong>history</strong> reaches. The UI
 * says so instead of presenting an empty history as "never changed".
 */
@Component
class RetentionJob {

    private static final Logger log = LoggerFactory.getLogger(RetentionJob.class);

    /** Minimum 14 days (Settings). */
    private static final int MINIMUM_DAYS = 14;

    private static final int DEFAULT_DAYS = 90;

    private final ChangeLogRepository changeLog;
    private final InstanceSettings settings;
    private final DSLContext db;

    RetentionJob(ChangeLogRepository changeLog, InstanceSettings settings, DSLContext db) {
        this.changeLog = changeLog;
        this.settings = settings;
        this.db = db;
    }

    @Scheduled(cron = "0 20 3 * * *")
    @Transactional
    public void clean() {
        int days = Math.max(MINIMUM_DAYS, settings.getInt(SettingKey.RETENTION_LOG_DAYS, DEFAULT_DAYS));
        OffsetDateTime cutoff = OffsetDateTime.now().minusDays(days);

        int removedEntries = changeLog.deleteOlderThan(cutoff);
        int removedMutations = db.deleteFrom(PROCESSED_MUTATION)
                .where(PROCESSED_MUTATION.PROCESSED_AT.lt(cutoff))
                .execute();

        if (removedEntries > 0 || removedMutations > 0) {
            log.info(
                    "retention: removed {} change log entries and {} processed mutations older than {} days",
                    removedEntries,
                    removedMutations,
                    days);
        }
    }
}
