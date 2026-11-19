package de.danielkononov.hiwiski.media.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.MEDIA;

import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.time.Duration;
import java.util.UUID;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;
import java.util.function.Supplier;
import org.jooq.DSLContext;
import org.jooq.impl.DSL;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.util.unit.DataSize;

/**
 * How much one member may store, and how many uploads are processed at once.
 *
 * <p>Any member could upload without end -- their own picture needs no share at all --
 * until the volume the database shares was full; and with virtual threads, nothing
 * bounded how many 25 MB uploads were read onto the heap at the same time.
 */
@Component
class UploadLimits {

    /** How long an upload waits for its turn before the server says it is busy. */
    private static final Duration WAIT = Duration.ofSeconds(30);

    /** What the app is told to wait before it tries again. */
    private static final int RETRY_AFTER_SECONDS = 10;

    private final DSLContext db;
    private final long quotaBytes;
    private final Semaphore turns;
    private final Duration wait;

    @Autowired
    UploadLimits(
            DSLContext db,
            @Value("${hiwiski.media-quota-per-member}") DataSize quota,
            @Value("${hiwiski.media-parallel-uploads}") int parallelUploads) {
        this(db, quota, parallelUploads, WAIT);
    }

    UploadLimits(DSLContext db, DataSize quota, int parallelUploads, Duration wait) {
        if (parallelUploads < 1) {
            throw new IllegalArgumentException("hiwiski.media-parallel-uploads must be at least 1");
        }
        this.db = db;
        this.quotaBytes = quota.toBytes();
        this.turns = new Semaphore(parallelUploads, true);
        this.wait = wait;
    }

    /**
     * Refuses an upload of {@code bytes} that would take the member past the quota.
     * Every image counts where its member uploaded it, also where the same bytes are
     * stored once for two of them; a quota of {@code 0} is none.
     */
    void checkQuota(UUID memberId, long bytes) {
        if (quotaBytes <= 0) {
            return;
        }
        long used = db.select(DSL.coalesce(DSL.sum(MEDIA.BYTE_SIZE), DSL.inline(java.math.BigDecimal.ZERO)))
                .from(MEDIA)
                .where(MEDIA.OWNER_ID.eq(memberId))
                .fetchOne(0, Long.class);
        if (used + bytes > quotaBytes) {
            throw new HiwiskiException(
                    HttpStatus.CONTENT_TOO_LARGE,
                    "media.quota_exceeded",
                    java.util.Map.of("usedBytes", String.valueOf(used), "quotaBytes", String.valueOf(quotaBytes)));
        }
    }

    /**
     * Runs {@code work} once one of the turns is free -- or, after half a minute
     * without one, says the server is busy, with a time to try again.
     */
    <T> T inTurn(Supplier<T> work) {
        boolean acquired;
        try {
            acquired = turns.tryAcquire(wait.toMillis(), TimeUnit.MILLISECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            acquired = false;
        }
        if (!acquired) {
            throw new HiwiskiException(
                    HttpStatus.SERVICE_UNAVAILABLE,
                    "media.busy",
                    java.util.Map.of(HiwiskiException.RETRY_AFTER_SECONDS, String.valueOf(RETRY_AFTER_SECONDS)));
        }
        try {
            return work.get();
        } finally {
            turns.release();
        }
    }
}
