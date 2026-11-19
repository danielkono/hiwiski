package de.danielkononov.hiwiski.admin.internal;

import com.exceptionfactory.jagged.x25519.X25519KeyPairGenerator;
import de.danielkononov.hiwiski.identity.SetupBackupKey;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.platform.InstanceSettings;
import de.danielkononov.hiwiski.platform.SettingKey;
import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.util.Base64;
import java.util.Optional;
import org.springframework.stereotype.Component;

/**
 * The backup key pair.
 *
 * <p><strong>The server encrypts at night without knowing the password.</strong> A
 * password it kept to encrypt with would lie on the server in the clear. Instead it
 * keeps the public key (an age X25519 recipient) and the private key wrapped with the
 * password; every archive carries that wrapped key in its header, so restoring needs the
 * file and the password, nothing else.
 */
@Component
class BackupKeys implements SetupBackupKey {

    /** As for member passwords. */
    static final int MINIMUM_LENGTH = 8;

    private final InstanceSettings settings;

    BackupKeys(InstanceSettings settings) {
        this.settings = settings;
    }

    /** The key in use: what every new archive is encrypted to and carries. */
    record Current(String recipient, KeySlot slot) {}

    Optional<Current> current() {
        var recipient = settings.find(SettingKey.BACKUP_KEY_RECIPIENT);
        var slot = settings.find(SettingKey.BACKUP_KEY_SLOT)
                .flatMap(encoded -> KeySlot.fromBytes(Base64.getDecoder().decode(encoded)));
        return recipient.isPresent() && slot.isPresent()
                ? Optional.of(new Current(recipient.get(), slot.get()))
                : Optional.empty();
    }

    /** {@code 409 admin.backup_password_missing} on an instance set up before backups were encrypted. */
    Current require() {
        return current().orElseThrow(() -> HiwiskiException.conflict("admin.backup_password_missing"));
    }

    /**
     * A new key pair, wrapped with {@code password}: at setup, and when the password is
     * forgotten. Archives made before open only with the password they were made with.
     */
    @Override
    public void create(String password) {
        requireStrong(password);
        KeyPair pair;
        try {
            pair = new X25519KeyPairGenerator().generateKeyPair();
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("could not make a backup key", e);
        }
        long counter = current().map(current -> current.slot().counter() + 1).orElse(1L);
        store(pair.getPublic().toString(), KeySlot.wrap(pair.getPrivate().toString(), password, counter));
    }

    /**
     * Wraps the same private key with {@code newPassword}. The archives made with it
     * stay readable -- their headers are rewritten by the caller.
     *
     * @return the new slot
     */
    KeySlot change(String currentPassword, String newPassword) {
        Current current = require();
        String identity = current.slot()
                .unwrap(currentPassword == null ? "" : currentPassword)
                .orElseThrow(() -> HiwiskiException.invalid("admin.backup_password_wrong"));
        requireStrong(newPassword);
        KeySlot slot = KeySlot.wrap(identity, newPassword, current.slot().counter() + 1);
        store(current.recipient(), slot);
        return slot;
    }

    /**
     * Takes over an archive's key -- restored on a fresh server, the backups from then
     * on open with the password just typed.
     */
    void adopt(String recipient, String identity, String password) {
        store(recipient, KeySlot.wrap(identity, password, 1));
    }

    static void requireStrong(String password) {
        if (password == null || password.length() < MINIMUM_LENGTH) {
            throw HiwiskiException.invalid("admin.backup_password_too_short", "minimum", MINIMUM_LENGTH);
        }
    }

    private void store(String recipient, KeySlot slot) {
        settings.put(SettingKey.BACKUP_KEY_RECIPIENT, recipient, null);
        settings.put(SettingKey.BACKUP_KEY_SLOT, Base64.getEncoder().encodeToString(slot.toBytes()), null);
    }
}
