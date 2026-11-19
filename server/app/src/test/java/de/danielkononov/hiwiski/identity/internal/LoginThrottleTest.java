package de.danielkononov.hiwiski.identity.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import org.junit.jupiter.api.Test;

class LoginThrottleTest {

    /** A clock the test moves. */
    private static final class Moving extends Clock {
        Instant now = Instant.parse("2026-10-08T10:00:00Z");

        @Override
        public Instant instant() {
            return now;
        }

        @Override
        public ZoneOffset getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(java.time.ZoneId zone) {
            return this;
        }
    }

    /** Made-up usernames in a loop no longer pile up for good. */
    @Test
    void oldAttemptsAreForgotten() {
        var clock = new Moving();
        var throttle = new LoginThrottle(clock);
        for (int i = 0; i < 1000; i++) {
            throttle.admit("random-" + i, "10.0." + (i / 250) + "." + (i % 250));
        }
        assertThat(throttle.tracked()).isEqualTo(1000);
        assertThat(throttle.trackedClients()).isEqualTo(1000);

        clock.now = clock.now.plus(Duration.ofMinutes(16));
        throttle.removeStale();

        assertThat(throttle.tracked()).isZero();
        assertThat(throttle.trackedClients()).isZero();
    }

    /**
     * A loop through made-up usernames meets the budget
     * of its address, not a fresh count per name.
     */
    @Test
    void oneAddressHasABudgetAcrossUsernames() {
        var clock = new Moving();
        var throttle = new LoginThrottle(clock);
        for (int i = 0; i < LoginThrottle.CLIENT_CAPACITY; i++) {
            throttle.admit("random-" + i, "203.0.113.7");
        }
        assertThatThrownBy(() -> throttle.admit("random-x", "203.0.113.7"))
                .isInstanceOfSatisfying(HiwiskiException.class, e -> {
                    assertThat(e.code()).isEqualTo("auth.too_many_attempts");
                    assertThat(e.params()).containsEntry(HiwiskiException.RETRY_AFTER_SECONDS, "10");
                });
        // Another address is not affected.
        throttle.admit("random-y", "198.51.100.1");

        // It refills: one more attempt after the refill time.
        clock.now = clock.now.plus(LoginThrottle.CLIENT_REFILL);
        throttle.admit("random-z", "203.0.113.7");
    }

    /** A successful sign-in does not count against the address. */
    @Test
    void successesCostNothing() {
        var throttle = new LoginThrottle(new Moving());
        for (int i = 0; i < 3 * LoginThrottle.CLIENT_CAPACITY; i++) {
            throttle.admit("anna", "192.168.1.20");
            throttle.succeeded("anna", "192.168.1.20");
        }
        assertThat(throttle.trackedClients()).isZero();
    }

    @Test
    void anIpv6ClientCountsByItsSlash64() {
        assertThat(ClientAddress.of("2001:db8:1:2:aaaa::1")).isEqualTo(ClientAddress.of("2001:db8:1:2:bbbb::2"));
        assertThat(ClientAddress.of("2001:db8:1:3::1")).isNotEqualTo(ClientAddress.of("2001:db8:1:2::1"));
        assertThat(ClientAddress.of("192.168.1.20")).isEqualTo("192.168.1.20");
    }

    /**
     * An outsider guessing at a known username slows
     * only themselves -- its owner, from their own address, is let in at once.
     */
    @Test
    void anOutsiderCannotKeepTheOwnerOut() {
        var throttle = new LoginThrottle(new Moving());
        for (int i = 0; i < 5; i++) {
            throttle.admit("anna", "203.0.113.9");
        }
        assertThatThrownBy(() -> throttle.admit("anna", "203.0.113.9"))
                .isInstanceOf(HiwiskiException.class);

        throttle.admit("anna", "192.168.1.20");
    }

    /**
     * Guesses from many addresses meet one ceiling per
     * username; a known client does not.
     */
    @Test
    void oneUsernameHasACeilingAcrossAddresses() {
        var clock = new Moving();
        var throttle = new LoginThrottle(clock);
        throttle.admit("anna", "192.168.1.20");
        throttle.succeeded("anna", "192.168.1.20");

        for (int i = 0; i < LoginThrottle.USER_CAPACITY; i++) {
            throttle.admit("Anna", "2001:db8:" + Integer.toHexString(i) + "::/64");
        }
        assertThatThrownBy(() -> throttle.admit("anna", "2001:db8:ffff::/64"))
                .isInstanceOfSatisfying(HiwiskiException.class, e -> {
                    assertThat(e.code()).isEqualTo("auth.too_many_attempts");
                    assertThat(e.params()).containsEntry(HiwiskiException.RETRY_AFTER_SECONDS, "60");
                });
        // Another username is not affected.
        throttle.admit("ben", "2001:db8:ffff::/64");
        // The member's own address and own installation still get in.
        throttle.admit("anna", "192.168.1.20");
        throttle.admit("anna", "198.51.100.7", () -> true);

        // One more a minute for everyone else.
        clock.now = clock.now.plus(LoginThrottle.USER_REFILL);
        throttle.admit("anna", "2001:db8:fffe::/64");
        assertThatThrownBy(() -> throttle.admit("anna", "2001:db8:fffd::/64")).isInstanceOf(HiwiskiException.class);
    }

    /** A known address stays known for thirty days, and only so many per username. */
    @Test
    void knownAddressesAreForgotten() {
        var clock = new Moving();
        var throttle = new LoginThrottle(clock);
        throttle.admit("anna", "192.168.1.20");
        throttle.succeeded("anna", "192.168.1.20");
        for (int i = 0; i < LoginThrottle.USER_CAPACITY; i++) {
            throttle.admit("anna", "10.9." + (i / 200) + "." + (i % 200));
        }
        clock.now = clock.now.plus(LoginThrottle.KNOWN_FOR).plusSeconds(1);
        throttle.removeStale();
        assertThat(throttle.trackedUsers()).isZero();

        // The ceiling has refilled by now; spend it again from strangers.
        for (int i = 0; i < LoginThrottle.USER_CAPACITY; i++) {
            throttle.admit("anna", "10.8." + (i / 200) + "." + (i % 200));
        }
        assertThatThrownBy(() -> throttle.admit("anna", "192.168.1.20")).isInstanceOf(HiwiskiException.class);
    }

    /** The ceiling does not count a device that is asked about only when it matters. */
    @Test
    void theDeviceIsAskedAboutOnlyAtTheCeiling() {
        var throttle = new LoginThrottle(new Moving());
        int[] asked = {0};
        for (int i = 0; i < LoginThrottle.USER_CAPACITY; i++) {
            throttle.admit("anna", "10.7.0." + i, () -> {
                asked[0]++;
                return false;
            });
        }
        assertThat(asked[0]).isZero();
        assertThatThrownBy(() -> throttle.admit("anna", "10.7.1.1", () -> {
                    asked[0]++;
                    return false;
                }))
                .isInstanceOf(HiwiskiException.class);
        assertThat(asked[0]).isEqualTo(1);
    }

    /**
     * The username is the key of the throttle's maps. Sent megabytes long, each sign-in
     * without an account stayed on the heap for minutes; cut to what a real one can be,
     * everything beyond is one and the same nobody.
     */
    @Test
    void anOverlongUsernameIsCountedByItsBeginning() {
        var throttle = new LoginThrottle(new Moving());
        String beginning = "u".repeat(LoginThrottle.MAX_NAME_LENGTH);

        throttle.admit(beginning + "a".repeat(100_000), "10.0.0.1");
        throttle.admit(beginning + "b".repeat(100_000), "10.0.0.1");

        assertThat(throttle.tracked()).isEqualTo(1);
        assertThat(throttle.trackedUsers()).isEqualTo(1);
    }
}
