package de.danielkononov.hiwiski.support;

import static de.danielkononov.hiwiski.db.generated.Tables.EVENT_PUBLICATION;

import java.time.Duration;
import java.time.Instant;
import org.jooq.DSLContext;

/**
 * Waits until the follow-up listeners are done.
 *
 * <p>Re-parsing links and writing a revision happen <strong>after the commit</strong>, in a
 * transaction of their own: a failure there must not bring down the mutation that was just
 * saved. For a test this means it has to wait -- and wait for a
 * <em>state</em>, not for a number of milliseconds. A {@code sleep} would sometimes be too
 * short on the build server and always too long here.
 */
public final class FollowUps {

    private FollowUps() {}

    private static final Duration LIMIT = Duration.ofSeconds(10);

    /** Returns as soon as no unfinished event is left open. */
    public static void await(DSLContext db) {
        Instant deadline = Instant.now().plus(LIMIT);
        while (Instant.now().isBefore(deadline)) {
            int open = db.fetchCount(EVENT_PUBLICATION, EVENT_PUBLICATION.COMPLETION_DATE.isNull());
            if (open == 0) {
                // The entry is set on completion; after that the follow-up is really done
                // and not merely invisible for the moment.
                return;
            }
            try {
                Thread.sleep(25);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
        }
        throw new AssertionError("The follow-up listeners did not finish within " + LIMIT);
    }

    /**
     * Like {@link #await}, but gives up quietly: for the cleaner between tests. One
     * follow-up that never finishes -- a broken listener -- fails the test that caused
     * it, not every test after it.
     */
    public static void settle(DSLContext db) {
        try {
            await(db);
        } catch (AssertionError stuck) {
            // The test that left it behind has already been reported.
        }
    }
}
