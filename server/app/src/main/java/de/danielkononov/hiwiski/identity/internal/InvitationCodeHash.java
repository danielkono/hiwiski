package de.danielkononov.hiwiski.identity.internal;

import java.util.Locale;
import org.springframework.security.crypto.argon2.Argon2PasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

/**
 * What is stored of an invitation code: a slow, salted hash.
 *
 * <p>A code is seven characters from 31, about 2.75·10¹⁰ possibilities. Under plain
 * SHA-256 a GPU tried them all in seconds, so a database dump or a backup archive gave
 * away every open invitation -- a family account in its groups for whoever redeems it
 * first. Argon2id with its own salt per code makes each one cost a run of 8 MiB:
 * trying them all takes years per invitation, and an invitation lives seven days at
 * most.
 *
 * <p>Lighter than a password's run (64 MiB, {@link PasswordEncoderConfig}): a preview
 * checks the code against every open invitation, since a salted hash cannot be looked
 * up. A family has a handful open at a time, and each wrong code counts against the
 * client's budget first ({@link InvitationService}). Like passwords, only a few runs
 * happen at once.
 */
@Component
class InvitationCodeHash {

    private final PasswordEncoder slow =
            new BoundedPasswordEncoder(new Argon2PasswordEncoder(16, 32, 1, 1 << 13, 3), 4);

    /** A new hash, with a salt of its own. */
    String hash(String code) {
        return slow.encode(normalize(code));
    }

    /** Whether {@code code} is the one {@code stored} was made from. */
    boolean matches(String code, String stored) {
        if (stored == null) {
            return false;
        }
        return slow.matches(normalize(code), stored);
    }

    /** Upper case, without the dash the UI shows and without spaces. */
    static String normalize(String code) {
        return code == null ? "" : code.replace("-", "").replace(" ", "").toUpperCase(Locale.ROOT);
    }
}
