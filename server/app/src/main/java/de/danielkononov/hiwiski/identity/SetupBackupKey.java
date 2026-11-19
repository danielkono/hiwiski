package de.danielkononov.hiwiski.identity;

/**
 * Makes the backup key from the password the setup wizard asks for.
 *
 * <p>The wizard is {@code identity}'s; the key is {@code admin}'s, and {@code admin}
 * already knows {@code identity}. So {@code admin} registers itself here instead of the
 * wizard calling it -- the same inversion as {@code RestoreCarryOver}.
 */
public interface SetupBackupKey {

    /** In the wizard's transaction: a failure leaves no family behind either. */
    void create(String backupPassword);
}
