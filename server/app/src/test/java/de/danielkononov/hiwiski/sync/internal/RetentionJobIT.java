package de.danielkononov.hiwiski.sync.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.CHANGE_LOG;
import static de.danielkononov.hiwiski.db.generated.Tables.PROCESSED_MUTATION;
import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.time.OffsetDateTime;
import java.util.Map;
import java.util.UUID;
import org.jooq.DSLContext;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * The daily cleanup.
 *
 * <p>The test lives in the same package as the job -- the job is package-private, and it
 * should stay that way: nothing public outside the module root package except the
 * interfaces. An access path just for the test would be production
 * code that nobody uses.
 */
@IntegrationTest
class RetentionJobIT {

    @Autowired RestTestClient rest;

    @Autowired DSLContext db;

    @Autowired RetentionJob retention;

    @Test
    void logAndIdempotencyExpireTogether() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);
        device.push(SyncClient.mutation("TODO_LIST", UUID.randomUUID(), null, Map.of("name", "Haushalt")));

        assertThat(db.fetchCount(CHANGE_LOG)).isPositive();
        assertThat(db.fetchCount(PROCESSED_MUTATION)).isPositive();

        // 100 days ago -- beyond the default of 90.
        var longAgo = OffsetDateTime.now().minusDays(100);
        db.update(CHANGE_LOG).set(CHANGE_LOG.RECORDED_AT, longAgo).execute();
        db.update(PROCESSED_MUTATION).set(PROCESSED_MUTATION.PROCESSED_AT, longAgo).execute();

        retention.clean();

        // Both with the same retention period: a retry without its log entry could no
        // longer answer anything.
        assertThat(db.fetchCount(CHANGE_LOG)).isZero();
        assertThat(db.fetchCount(PROCESSED_MUTATION)).isZero();
    }

    @Test
    void freshEntriesStay() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);
        device.push(SyncClient.mutation("TODO_LIST", UUID.randomUUID(), null, Map.of("name", "Haushalt")));

        retention.clean();

        // Both of them: a cleanup that took every processed mutation would make a
        // client's retry apply its mutations twice instead of answering "duplicate".
        assertThat(db.fetchCount(CHANGE_LOG)).isPositive();
        assertThat(db.fetchCount(PROCESSED_MUTATION)).isPositive();
    }

    /** The cutoff is the retention period: 89 days stay, 91 days go. */
    @Test
    void theBoundaryIsTheRetentionPeriod() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);
        UUID young = UUID.randomUUID();
        UUID old = UUID.randomUUID();
        device.push(SyncClient.mutation("TODO_LIST", young, null, Map.of("name", "Young")));
        device.push(SyncClient.mutation("TODO_LIST", old, null, Map.of("name", "Old")));
        db.update(CHANGE_LOG)
                .set(CHANGE_LOG.RECORDED_AT, OffsetDateTime.now().minusDays(89))
                .where(CHANGE_LOG.ENTITY_ID.eq(young))
                .execute();
        db.update(CHANGE_LOG)
                .set(CHANGE_LOG.RECORDED_AT, OffsetDateTime.now().minusDays(91))
                .where(CHANGE_LOG.ENTITY_ID.eq(old))
                .execute();

        retention.clean();

        assertThat(db.fetchCount(CHANGE_LOG, CHANGE_LOG.ENTITY_ID.eq(young))).isPositive();
        assertThat(db.fetchCount(CHANGE_LOG, CHANGE_LOG.ENTITY_ID.eq(old))).isZero();
    }
}
