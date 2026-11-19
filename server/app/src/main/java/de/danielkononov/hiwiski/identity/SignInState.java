package de.danielkononov.hiwiski.identity;

/**
 * Who may sign in, and with what: passwords, disabled members, revoked devices.
 *
 * <p>A backup restore puts back the family's content as it was, but not this. A phone
 * revoked after the backup, or a password changed since, must stay revoked and changed
 * -- otherwise restoring last Sunday's backup to undo a deletion re-opened the door
 * the family had just closed. The restore takes a snapshot before it replaces the
 * tables and carries it over afterwards, in the same transaction.
 */
public interface SignInState {

    /** The current state, taken before the restore replaces the tables. */
    Snapshot capture();

    /**
     * Puts the captured state back over the restored rows: the current password,
     * forced change and disabled state for every member that exists in both; every
     * device as it is now -- revoked ones revoked, its token, when it was last seen and
     * whether it stays signed in; devices registered since the backup
     * kept, as long as their member exists. What only the archive knows -- the archive
     * of another instance, restored to move to a new server -- stays as archived.
     */
    void carryOver(Snapshot snapshot);

    /** Opaque to everyone but the identity module. */
    interface Snapshot {}
}
