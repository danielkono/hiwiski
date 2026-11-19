package de.danielkononov.hiwiski.identity.internal;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/** Invitation codes under a slow, salted hash. */
class InvitationCodeHashTest {

    private final InvitationCodeHash hash = new InvitationCodeHash();

    @Test
    void aNewCodeGetsArgon2WithASaltOfItsOwn() {
        String first = hash.hash("K7M4QXP");
        String second = hash.hash("K7M4QXP");
        assertThat(first).startsWith("$argon2id$").doesNotContain("K7M4QXP");
        // The same code, another salt: a dump cannot be matched against one table.
        assertThat(first).isNotEqualTo(second);
        assertThat(hash.matches("K7M4QXP", first)).isTrue();
        assertThat(hash.matches("K7M4QXP", second)).isTrue();
        assertThat(hash.matches("K7M4QXQ", first)).isFalse();
    }

    @Test
    void theCodeIsNormalizedAsTheUiShowsIt() {
        String stored = hash.hash("K7M4QXP");
        assertThat(hash.matches("k7m-4qxp", stored)).isTrue();
        assertThat(hash.matches(" K7M 4QXP ", stored)).isTrue();
    }

    @Test
    void nothingStoredMatchesNothing() {
        assertThat(hash.matches("K7M4QXP", null)).isFalse();
    }
}
