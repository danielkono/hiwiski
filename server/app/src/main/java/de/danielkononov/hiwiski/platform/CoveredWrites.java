package de.danielkononov.hiwiski.platform;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * For a follow-up that works on an item after a write and reads it as it is by then --
 * its references parsed anew, its search entry rebuilt: whether a run already done
 * covers a write, so that the write needs no run of its own.
 *
 * <p>Many writes to the parts of one item at once each ask for the same follow-up on
 * it: a mind map's elements brought back with their page, a thousand of them, read the
 * whole map a thousand times over. A run reads whatever was committed when it started,
 * so it covers every write up to the change sequence's position at that moment -- the
 * sequence's row lock makes number order and commit order the same. A write at or
 * before the position of a finished run is skipped.
 *
 * <p>Kept in memory, per item: after a restart every write gets its run again, which is
 * only slower. A run counts once its transaction has committed -- one rolled back
 * covers nothing.
 *
 * @param <K> what identifies the item the follow-up works on
 */
public final class CoveredWrites<K> {

    private final ChangeSequence sequence;
    private final Map<K, Long> coveredUpTo = new ConcurrentHashMap<>();

    public CoveredWrites(ChangeSequence sequence) {
        this.sequence = sequence;
    }

    /**
     * Runs {@code followUp} for {@code item} unless a finished run already read past the
     * write at {@code version}.
     *
     * @param version the position of the write in the change sequence; 0 where it is not
     *     known, and then the follow-up always runs
     */
    public void run(K item, long version, Runnable followUp) {
        if (version > 0 && coveredUpTo.getOrDefault(item, 0L) >= version) {
            return;
        }
        long position = sequence.current();
        followUp.run();
        afterCommit(() -> coveredUpTo.merge(item, position, Math::max));
    }

    private static void afterCommit(Runnable action) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            action.run();
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                action.run();
            }
        });
    }
}
