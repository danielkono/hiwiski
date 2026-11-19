package de.danielkononov.hiwiski.platform;

/**
 * The sequence counter of the change log.
 *
 * <p>Deliberately not a Postgres {@code SEQUENCE}: a sequence hands out numbers on
 * insert, not on commit. Two parallel transactions could then become visible in the
 * order 2, 1, and a client pulling in between would skip number 1 forever. The row lock
 * held until commit guarantees that commit order and number order match.
 */
public interface ChangeSequence {

    /**
     * Draws the next number. Must run in the caller's transaction -- the lock only holds
     * until its commit.
     */
    long next();

    /** The most recently issued number, without drawing one. */
    long current();
}
