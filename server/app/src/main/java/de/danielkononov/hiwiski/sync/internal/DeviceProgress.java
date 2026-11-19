package de.danielkononov.hiwiski.sync.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.DEVICE;

import java.time.OffsetDateTime;
import java.util.UUID;
import org.jooq.DSLContext;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * What the device reports along with every pull.
 *
 * <p>Without {@code last_sync_seq} and {@code pending_count} there would be no sync
 * state in the device list -- and that is exactly what the design asks for
 * (identity).
 *
 * <p>The table belongs to {@code identity}. Only the write lives here, because the value
 * arises during the pull; the alternative would be a callback from {@code sync} to
 * {@code identity}, and that would need an interface for two numbers.
 */
@Component
class DeviceProgress {

    private final DSLContext db;

    DeviceProgress(DSLContext db) {
        this.db = db;
    }

    @Transactional
    void record(UUID deviceId, long lastSeq, Integer pendingCount) {
        db.update(DEVICE)
                .set(DEVICE.LAST_SYNC_SEQ, lastSeq)
                .set(DEVICE.PENDING_COUNT, pendingCount == null ? 0 : Math.max(0, pendingCount))
                .set(DEVICE.LAST_SEEN_AT, OffsetDateTime.now())
                .where(DEVICE.ID.eq(deviceId))
                .execute();
    }
}
