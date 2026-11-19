package de.danielkononov.hiwiski.calendar.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.CALENDAR_SUBSCRIPTION;

import de.danielkononov.hiwiski.sync.EntityWritten;
import org.jooq.DSLContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;

/**
 * A new subscription is fetched right away, not at the next quarter past.
 *
 * <p>Subscriptions arrive through sync like every other item, and the regular job only
 * runs once an hour. Whoever subscribed to the school holidays saw an empty calendar for
 * up to an hour and had to know about "Refresh". After the commit, and in the background:
 * a slow source must not hold up the sync, and a failure is noted on the subscription
 * like on every other fetch.
 *
 * <p><strong>Without a transaction of its own</strong>, unlike the default of the
 * annotation. The fetch then runs exactly as when someone taps "Refresh": every write
 * commits by itself. Inside one bracket, the events written would hold the row lock on
 * the change sequence until the end — and {@code recordSuccess}, which writes in a
 * transaction of its own, would wait for it forever while the bracket waits for
 * {@code recordSuccess}. Postgres sees no deadlock in that, and every write on the
 * server queued up behind it.
 */
@Component
class SubscriptionFirstFetch {

    private static final Logger log = LoggerFactory.getLogger(SubscriptionFirstFetch.class);

    private final DSLContext db;
    private final SubscriptionService subscriptions;

    SubscriptionFirstFetch(DSLContext db, SubscriptionService subscriptions) {
        this.db = db;
        this.subscriptions = subscriptions;
    }

    @ApplicationModuleListener(propagation = Propagation.NOT_SUPPORTED)
    void onEntityWritten(EntityWritten event) {
        // Not the server's own writes: recording a failed fetch writes the subscription,
        // and answering that with another fetch looped for as long as it kept failing.
        if (!CalendarSyncTypes.SUBSCRIPTION_TYPE.equals(event.entityType()) || event.deleted() || event.byServer()) {
            return;
        }
        boolean neverFetched = db.fetchExists(db.selectOne()
                .from(CALENDAR_SUBSCRIPTION)
                .where(CALENDAR_SUBSCRIPTION.ID.eq(event.entityId()))
                .and(CALENDAR_SUBSCRIPTION.DELETED_AT.isNull())
                .and(CALENDAR_SUBSCRIPTION.LAST_SYNC_AT.isNull()));
        if (!neverFetched) {
            return;
        }
        try {
            subscriptions.refresh(event.entityId());
        } catch (RuntimeException e) {
            // Noted on the subscription already; the listener itself is done.
            log.info("first fetch of subscription {} failed: {}", event.entityId(), e.getMessage());
        }
    }
}
