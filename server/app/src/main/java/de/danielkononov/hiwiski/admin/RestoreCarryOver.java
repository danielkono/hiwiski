package de.danielkononov.hiwiski.admin;

/**
 * Something a backup restore must not take from the archive: a domain module's bearer
 * secrets, such as a wall board's or a calendar feed's address.
 *
 * <p>An archive holds them in plaintext. A family whose archive leaked replaces those
 * addresses (site: "Backups") -- restoring that archive, or any older one, must not make
 * the leaked addresses work again. The restore captures the current values before it
 * replaces the tables and carries them over afterwards, in the same transaction, for
 * every row that exists in both. Rows only the archive knows keep the archive's value.
 *
 * <p>The same inversion as {@link Restorable}: {@code admin} does not know the tables;
 * the domain modules register what they need carried over.
 */
public interface RestoreCarryOver {

    /** The current state, taken before the restore replaces the tables. */
    Snapshot capture();

    /** Puts the captured state back over the restored rows. */
    void carryOver(Snapshot snapshot);

    /** Opaque to everyone but the module that captured it. */
    interface Snapshot {}
}
