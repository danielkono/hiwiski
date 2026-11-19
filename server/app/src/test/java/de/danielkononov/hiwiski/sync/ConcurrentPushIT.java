package de.danielkononov.hiwiski.sync;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.sql.Connection;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import java.util.function.Supplier;
import javax.sql.DataSource;
import org.jooq.DSLContext;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * Pushes that run at the same time.
 *
 * <p>Writers are serialized by the row lock of the change sequence. Whatever a push
 * decides on -- the item as it stands, whether the mutation was already processed --
 * has to be read under that lock; read before it, it may be stale by the time the push
 * gets its turn. The tests hold the lock themselves while the pushes arrive, so both
 * are waiting at the same point, and then let them through one after the other.
 */
@IntegrationTest
class ConcurrentPushIT {

    private static final String LIST = "TODO_LIST";

    @Autowired RestTestClient rest;
    @Autowired DataSource dataSource;
    @Autowired DSLContext db;

    /** Runs the pushes while the sequence is locked, and releases it once all wait. */
    private List<List<Map<String, Object>>> whileTheSequenceIsHeld(
            List<Supplier<List<Map<String, Object>>>> pushes) throws Exception {
        try (Connection holder = dataSource.getConnection()) {
            holder.setAutoCommit(false);
            try (var statement = holder.createStatement()) {
                statement.executeUpdate("update change_sequence set seq = seq");
            }
            var running = pushes.stream().map(CompletableFuture::supplyAsync).toList();
            waitForBlockedSessions(pushes.size());
            holder.rollback();
            return running.stream()
                    .map(future -> {
                        try {
                            return future.get(30, TimeUnit.SECONDS);
                        } catch (Exception e) {
                            throw new IllegalStateException(e);
                        }
                    })
                    .toList();
        }
    }

    private void waitForBlockedSessions(int count) throws InterruptedException {
        Instant deadline = Instant.now().plus(Duration.ofSeconds(20));
        while (Instant.now().isBefore(deadline)) {
            int waiting = ((Number) db.fetchValue(
                            "select count(*) from pg_stat_activity where wait_event_type = 'Lock'"))
                    .intValue();
            if (waiting >= count) {
                return;
            }
            Thread.sleep(20);
        }
        throw new IllegalStateException("the pushes never reached the sequence lock");
    }

    /**
     * Two devices change the same field on the same version. One wins, the other is told
     * -- before, both read the item before the lock, both passed the field check, and the
     * second overwrote the first without a conflict.
     */
    @Test
    void twoEditsOfTheSameFieldGiveOneConflict() throws Exception {
        var phone = Family.setUp(rest);
        var laptop = Family.login(rest, "anna", "geheim-genug", "Laptop");
        var phoneDevice = new SyncClient(rest, phone);
        var laptopDevice = new SyncClient(rest, laptop);

        UUID listId = UUID.randomUUID();
        var created = phoneDevice.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Haushalt")));
        long version = ((Number) created.getFirst().get("version")).longValue();

        var results = whileTheSequenceIsHeld(List.of(
                () -> phoneDevice.push(SyncClient.mutation(LIST, listId, version, Map.of("name", "Putzen"))),
                () -> laptopDevice.push(SyncClient.mutation(LIST, listId, version, Map.of("name", "Einkauf")))));

        assertThat(results.stream().map(result -> result.getFirst().get("status")))
                .containsExactlyInAnyOrder("applied", "conflict");
    }

    /**
     * A device times out and sends the same mutation again while the first request still
     * runs. The second has to answer {@code duplicate} -- before, both found no processed
     * mutation, and the second ran into the primary key and reported a create that had
     * worked as rejected.
     */
    @Test
    void aRetryWhileTheFirstRequestRunsIsADuplicate() throws Exception {
        var anna = Family.setUp(rest);
        var device = new SyncClient(rest, anna);
        var create = SyncClient.mutation(LIST, UUID.randomUUID(), null, Map.of("name", "Haushalt"));

        var results = whileTheSequenceIsHeld(List.of(() -> device.push(create), () -> device.push(create)));

        assertThat(results.stream().map(result -> result.getFirst().get("status")))
                .containsExactlyInAnyOrder("applied", "duplicate");
    }
}
