package de.danielkononov.hiwiski.identity.internal;

import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.util.Map;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;

/**
 * At most a few password hashes at a time.
 *
 * <p>Each Argon2 run takes 64 MiB. With virtual threads nothing bounds how many requests
 * run at once, and a sign-in with a made-up username still costs a full run (the decoy
 * check against username enumeration). A few dozen parallel sign-ins took several GiB of
 * heap -- on a Raspberry Pi or a NAS that is the end of the server, without an account.
 * Here the hashes wait for each other; whoever waits too long gets the 429 of a sign-in
 * that came too soon, and the memory a hash needs stays bounded.
 */
final class BoundedPasswordEncoder implements PasswordEncoder {

    /** How long a hash waits for a turn before the request is turned away. */
    private static final long WAIT_SECONDS = 10;

    private final PasswordEncoder delegate;
    private final Semaphore turns;

    BoundedPasswordEncoder(PasswordEncoder delegate, int concurrent) {
        this.delegate = delegate;
        this.turns = new Semaphore(concurrent, true);
    }

    /**
     * One hash per 256 MiB of heap, between one and four: two on a small home server,
     * never so many that they take the heap the rest of the server needs.
     */
    static int concurrentFor(long maxHeapBytes) {
        long perHash = 256L * 1024 * 1024;
        return (int) Math.max(1, Math.min(4, maxHeapBytes / perHash));
    }

    @Override
    public String encode(CharSequence rawPassword) {
        acquire();
        try {
            return delegate.encode(rawPassword);
        } finally {
            turns.release();
        }
    }

    @Override
    public boolean matches(CharSequence rawPassword, String encodedPassword) {
        acquire();
        try {
            return delegate.matches(rawPassword, encodedPassword);
        } finally {
            turns.release();
        }
    }

    @Override
    public boolean upgradeEncoding(String encodedPassword) {
        return delegate.upgradeEncoding(encodedPassword);
    }

    private void acquire() {
        boolean acquired;
        try {
            acquired = turns.tryAcquire(WAIT_SECONDS, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            acquired = false;
        }
        if (!acquired) {
            throw new HiwiskiException(
                    HttpStatus.TOO_MANY_REQUESTS,
                    "auth.too_many_attempts",
                    Map.of(HiwiskiException.RETRY_AFTER_SECONDS, String.valueOf(WAIT_SECONDS)));
        }
    }
}
