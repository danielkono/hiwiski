package de.danielkononov.hiwiski.identity.internal;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.HexFormat;
import org.springframework.stereotype.Component;

/**
 * Randomness, hashes and the invitation code.
 *
 * <p>Two different schemes, and the difference matters:
 *
 * <ul>
 *   <li><strong>Passwords</strong> go through Argon2id. They are short and chosen by
 *       humans; a fast hash would let them be brute-forced.
 *   <li><strong>Device tokens</strong> go through SHA-256. They are 256 bits of
 *       randomness -- there is nothing to guess, and the hash has to be computed on
 *       every request. Argon2 would be no gain in security here, only a loss in
 *       response time.
 * </ul>
 *
 * <p>Invitation codes are short enough to guess and get a slow hash of their own
 * ({@link InvitationCodeHash}).
 */
@Component
class Secrets {

    private static final SecureRandom RANDOM = new SecureRandom();

    /**
     * The alphabet of the invitation code.
     *
     * <p>Without easily confused characters: no {@code 0} next to
     * {@code O}, no {@code 1} next to {@code I} and {@code L}. The code gets read out and
     * copied down.
     */
    private static final char[] CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ".toCharArray();

    private static final int CODE_LENGTH = 7;

    /** An opaque device token: 256 bits of randomness, URL-safe encoded. */
    String newToken() {
        byte[] bytes = new byte[32];
        RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    String hashToken(String token) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(token.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 is part of every JRE", e);
        }
    }

    String newInvitationCode() {
        StringBuilder code = new StringBuilder(CODE_LENGTH);
        for (int i = 0; i < CODE_LENGTH; i++) {
            code.append(CODE_ALPHABET[RANDOM.nextInt(CODE_ALPHABET.length)]);
        }
        return code.toString();
    }

    /**
     * The setup code: eight characters in two groups ({@code K7M4-2QXP}), from the
     * invitation code's alphabet -- it is read off a log and typed by hand. About 40
     * bits, and the setup refuses wrong ones beyond a few per address.
     */
    String newSetupCode() {
        StringBuilder code = new StringBuilder(9);
        for (int i = 0; i < 8; i++) {
            if (i == 4) {
                code.append('-');
            }
            code.append(CODE_ALPHABET[RANDOM.nextInt(CODE_ALPHABET.length)]);
        }
        return code.toString();
    }

    /**
     * A temporary password that can be read out loud.
     *
     * <p>The same character set as the invitation code, for the same reason: the
     * administrator reads it out or writes it on a slip of paper.
     */
    String newTemporaryPassword() {
        StringBuilder password = new StringBuilder(12);
        for (int i = 0; i < 12; i++) {
            if (i == 4 || i == 8) {
                password.append('-');
            }
            password.append(CODE_ALPHABET[RANDOM.nextInt(CODE_ALPHABET.length)]);
        }
        return password.toString();
    }
}
