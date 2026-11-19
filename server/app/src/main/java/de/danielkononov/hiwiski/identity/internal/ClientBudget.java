package de.danielkononov.hiwiski.identity.internal;

import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.http.HttpStatus;

/**
 * A budget of attempts per client: a bucket that holds {@code capacity} attempts and
 * refills one every {@code refill}.
 *
 * <p>The per-username throttle ({@link LoginThrottle}) does not see a loop that sends a
 * new username every time -- a password spray, or a flood of made-up names whose decoy
 * checks each cost an Argon2 run. This one counts by where the requests come from.
 * Only what fails is meant to be spent: the caller gives the attempt back when it
 * succeeds, so a family signing in all evening never notices it.
 *
 * <p>In memory, like the username throttle: a restart is not an attack.
 */
final class ClientBudget {

    private record Bucket(double attempts, Instant updated) {}

    private final String code;
    private final int capacity;
    private final Duration refill;
    private final Clock clock;
    private final Map<String, Bucket> buckets = new ConcurrentHashMap<>();

    /**
     * @param code the error code of the 429, so the app can name what is waiting
     */
    ClientBudget(String code, int capacity, Duration refill, Clock clock) {
        this.code = code;
        this.capacity = capacity;
        this.refill = refill;
        this.clock = clock;
    }

    /**
     * Spends one attempt, or refuses with 429 when the client has none left.
     *
     * @throws HiwiskiException with {@code retryAfterSeconds}
     */
    void spend(String client) {
        Instant now = clock.instant();
        boolean[] refused = {false};
        Bucket bucket = buckets.compute(client, (ignored, current) -> {
            double attempts = available(current, now);
            if (attempts < 1) {
                refused[0] = true;
                return new Bucket(attempts, now);
            }
            return new Bucket(attempts - 1, now);
        });
        if (refused[0]) {
            double missing = 1 - bucket.attempts();
            long seconds = Math.max(1, (long) Math.ceil(missing * refill.toMillis() / 1000.0));
            throw new HiwiskiException(
                    HttpStatus.TOO_MANY_REQUESTS,
                    code,
                    Map.of(HiwiskiException.RETRY_AFTER_SECONDS, String.valueOf(seconds)));
        }
    }

    /** The attempt succeeded: it does not count against the client. */
    void refund(String client) {
        Instant now = clock.instant();
        buckets.computeIfPresent(client, (ignored, current) -> {
            double attempts = Math.min(capacity, available(current, now) + 1);
            return attempts >= capacity ? null : new Bucket(attempts, now);
        });
    }

    /** Clients whose bucket has filled up again are forgotten. */
    void removeStale() {
        Instant now = clock.instant();
        buckets.entrySet().removeIf(entry -> available(entry.getValue(), now) >= capacity);
    }

    /** How many clients are being counted -- for the test. */
    int tracked() {
        return buckets.size();
    }

    private double available(Bucket bucket, Instant now) {
        if (bucket == null) {
            return capacity;
        }
        double refilled = (double) Duration.between(bucket.updated(), now).toMillis() / refill.toMillis();
        return Math.min(capacity, bucket.attempts() + Math.max(0, refilled));
    }
}
