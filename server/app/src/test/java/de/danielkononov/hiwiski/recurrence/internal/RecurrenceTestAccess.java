package de.danielkononov.hiwiski.recurrence.internal;

import de.danielkononov.hiwiski.recurrence.Recurrence;

/**
 * The way into the package-private implementation without making it public.
 *
 * <p>Nothing public outside the module root package except the interfaces.
 * The golden test needs the implementation directly — after all, it
 * is the implementation it tests, not the interface.
 */
public final class RecurrenceTestAccess {

    private RecurrenceTestAccess() {}

    public static Recurrence create() {
        return new LibRecurRecurrence();
    }
}
