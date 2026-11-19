package de.danielkononov.hiwiski.calendar.internal;

import de.danielkononov.hiwiski.sync.ServerWrites;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * The note on the subscription: when last, how many, and whether something went wrong.
 *
 * <p><strong>A bean of its own, not a pair of methods on the service.</strong> {@code
 * REQUIRES_NEW} works only through the proxy; a call within the same instance bypasses
 * it, and the note would land in exactly the transaction that is being rolled back.
 * The same trap already struck once in {@code MutationApplier} — which is why it is
 * not set again here.
 *
 * <p><strong>And the note goes through the log, not via a direct UPDATE.</strong> When
 * clicking through, the subscription still said "Not synced yet" although the server had
 * long had the error in the column: the pull reads only the log, and what is not in it
 * does not exist for the devices. A direct UPDATE on a synced item is
 * always a bug — even when it is "only" a status field.
 */
@Component
class SubscriptionStatus {

    private final ServerWrites writes;

    SubscriptionStatus(ServerWrites writes) {
        this.writes = writes;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    void recordSuccess(UUID subscriptionId, UUID owner, int count) {
        Map<String, Object> fields = new LinkedHashMap<>();
        fields.put("lastSyncAt", OffsetDateTime.now().toString());
        fields.put("lastError", null);
        fields.put("importedCount", count);
        write(subscriptionId, owner, fields);
    }

    /**
     * The error note has to arrive <strong>precisely because</strong> the sync failed —
     * hence its own bracket.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    void recordFailure(UUID subscriptionId, UUID owner, String error) {
        Map<String, Object> fields = new LinkedHashMap<>();
        fields.put("lastError", error);
        write(subscriptionId, owner, fields);
    }

    private void write(UUID subscriptionId, UUID owner, Map<String, Object> fields) {
        writes.upsert(
                CalendarSyncTypes.SUBSCRIPTION_TYPE, subscriptionId, null, null, fields, owner);
    }
}
