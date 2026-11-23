package de.danielkononov.hiwiski.platform;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

/**
 * A follow-up runs once for writes that come together: a run reads what was committed
 * when it started, and so covers every write up to that position.
 */
class CoveredWritesTest {

    /** The change sequence, standing where a test puts it. */
    private static final class Sequence implements ChangeSequence {
        long position;

        @Override
        public long next() {
            return ++position;
        }

        @Override
        public long current() {
            return position;
        }
    }

    private final Sequence sequence = new Sequence();
    private final CoveredWrites<String> covered = new CoveredWrites<>(sequence);
    private final List<Long> runs = new ArrayList<>();

    private void written(long version) {
        covered.run("page", version, () -> runs.add(version));
    }

    @Test
    void writesARunHasReadPastNeedNoRunOfTheirOwn() {
        // A thousand elements brought back with their page, all committed before the
        // first of their follow-ups starts.
        sequence.position = 1_000;
        for (long version = 1; version <= 1_000; version++) {
            written(version);
        }
        assertThat(runs).containsExactly(1L);

        // A later write was not read yet.
        sequence.position = 1_001;
        written(1_001);
        assertThat(runs).containsExactly(1L, 1_001L);
    }

    @Test
    void aWriteOfUnknownPositionAlwaysRuns() {
        sequence.position = 10;
        written(5);
        written(0);
        written(0);
        assertThat(runs).containsExactly(5L, 0L, 0L);
    }

    @Test
    void eachItemOnItsOwn() {
        sequence.position = 10;
        covered.run("page", 5, () -> runs.add(1L));
        covered.run("other page", 5, () -> runs.add(2L));
        assertThat(runs).containsExactly(1L, 2L);
    }

    @Test
    void aRunThatFailedCoversNothing() {
        sequence.position = 10;
        assertThatThrownBy(() -> covered.run("page", 5, () -> {
                    throw new IllegalStateException("parse failed");
                }))
                .isInstanceOf(IllegalStateException.class);
        written(5);
        assertThat(runs).containsExactly(5L);
    }
}
