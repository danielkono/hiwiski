package de.danielkononov.hiwiski.identity.internal;

import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.time.Duration;
import java.time.Instant;
import java.util.Comparator;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.BooleanSupplier;
import org.springframework.http.HttpStatus;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Login attempts are <strong>slowed, not locked out</strong>.
 *
 * <p>A locked-out family has no support channel: whoever mistypes their own account
 * twenty times must not be shut out for an hour afterwards. A growing wait between
 * attempts still makes brute-forcing prohibitively expensive.
 *
 * <p>The wait is <strong>answered, not slept</strong>: an attempt too soon gets 429 with
 * {@code Retry-After}. Sleeping held a database connection per waiting request --
 * ten wrong passwords at once took the whole pool -- and parallel requests all read the
 * same old count, so they were not slowed at all. The attempt is now counted before the
 * password is checked, in one atomic step.
 *
 * <p>The wait counts per username <em>and</em> client address. Per username alone, an
 * outsider sending one wrong password a minute kept a known account in the 429 state
 * and its owner could not sign in at all -- a lockout after all, triggered by someone
 * else. Now the outsider slows only themselves.
 *
 * <p>Next to that there is a budget per client address: a loop that
 * sends a new username every time -- a password spray, or made-up names whose decoy
 * checks each cost a 64 MiB Argon2 run -- never meets the same username twice. Thirty
 * failed sign-ins from one address are free, then one every ten seconds.
 *
 * <p>And a <strong>ceiling per username across all addresses</strong>: with the wait per (username, address), an attacker with many
 * addresses -- one IPv6 /48 holds 65,536 /64s -- got a fresh count with each. A hundred
 * failed sign-ins for one username are free, from wherever; then one a minute, about
 * 1,500 a day. That ceiling must not turn into the lockout the per-address wait
 * removed, so it does not apply to an attempt from a <em>known</em> client: an app
 * installation that has signed in to this account before (its id is random and never
 * leaves the device), or an address this username signed in from in the last thirty
 * days. An outsider who spends the ceiling slows down only first sign-ins on a new
 * device from a new network; every phone and browser the member used before still
 * gets in at once, and a successful sign-in gives one attempt back.
 *
 * <p>In memory and not in the database: the counts do not survive a restart, and that is
 * how it should be -- a restart is not an attack.
 */
@Component
class LoginThrottle {

    private static final Duration WINDOW = Duration.ofMinutes(15);

    /** Mistakes that cost nothing: a forgotten password takes a few tries. */
    private static final int FREE = 5;

    private static final Duration STEP = Duration.ofSeconds(1);
    private static final Duration CEILING = Duration.ofMinutes(1);

    private record Attempts(int count, Instant last, Instant nextAllowed) {}

    /** Failed sign-ins one address has free. */
    static final int CLIENT_CAPACITY = 30;

    /** After those, one more every so often. */
    static final Duration CLIENT_REFILL = Duration.ofSeconds(10);

    /** Failed sign-ins one username has free, across all addresses. */
    static final int USER_CAPACITY = 100;

    /** After those, one more every so often -- for clients it does not know. */
    static final Duration USER_REFILL = Duration.ofMinutes(1);

    /** How long an address a username signed in from counts as known. */
    static final Duration KNOWN_FOR = Duration.ofDays(30);

    /** The most addresses remembered per username; the oldest goes first. */
    static final int KNOWN_PER_USER = 16;

    private final Map<String, Attempts> attempts = new ConcurrentHashMap<>();
    private final ClientBudget clients;
    private final ClientBudget users;
    /** Per username: the addresses it signed in from, and when last. */
    private final Map<String, Map<String, Instant>> knownClients = new ConcurrentHashMap<>();
    private final java.time.Clock clock;

    LoginThrottle() {
        this(java.time.Clock.systemUTC());
    }

    LoginThrottle(java.time.Clock clock) {
        this.clock = clock;
        this.clients = new ClientBudget("auth.too_many_attempts", CLIENT_CAPACITY, CLIENT_REFILL, clock);
        this.users = new ClientBudget("auth.too_many_attempts", USER_CAPACITY, USER_REFILL, clock);
    }

    /** {@link #admit(String, String, BooleanSupplier)} from a client nothing vouches for. */
    void admit(String username, String client) {
        admit(username, client, () -> false);
    }

    /**
     * Counts this attempt, or refuses it with 429 when it comes before the wait is over
     * -- for the username, or for the address it comes from.
     *
     * @param knownDevice whether the attempt comes from an installation that signed in to
     *     this account before; asked only once the username's ceiling is spent
     * @throws HiwiskiException {@code auth.too_many_attempts} with {@code retryAfterSeconds}
     */
    void admit(String username, String client, BooleanSupplier knownDevice) {
        clients.spend(client);
        Instant now = clock.instant();
        boolean[] refused = {false};
        Attempts entry = attempts.compute(key(username, client), (ignored, current) -> {
            if (current == null || current.last().plus(WINDOW).isBefore(now)) {
                return new Attempts(1, now, now);
            }
            if (now.isBefore(current.nextAllowed())) {
                refused[0] = true;
                return current;
            }
            int count = current.count() + 1;
            return new Attempts(count, now, now.plus(wait(count)));
        });
        if (refused[0]) {
            long seconds = Math.max(1, Duration.between(now, entry.nextAllowed()).toSeconds() + 1);
            throw new HiwiskiException(
                    HttpStatus.TOO_MANY_REQUESTS,
                    "auth.too_many_attempts",
                    Map.of(HiwiskiException.RETRY_AFTER_SECONDS, String.valueOf(seconds)));
        }
        try {
            users.spend(name(username));
        } catch (HiwiskiException ceilingReached) {
            if (!knownClient(username, client, now) && !knownDevice.getAsBoolean()) {
                throw ceilingReached;
            }
        }
    }

    void succeeded(String username, String client) {
        clients.refund(client);
        users.refund(name(username));
        attempts.remove(key(username, client));
        Instant now = clock.instant();
        Map<String, Instant> known = knownClients.computeIfAbsent(name(username), ignored -> new ConcurrentHashMap<>());
        known.put(client, now);
        while (known.size() > KNOWN_PER_USER) {
            known.entrySet().stream()
                    .min(Map.Entry.comparingByValue(Comparator.naturalOrder()))
                    .ifPresent(oldest -> known.remove(oldest.getKey(), oldest.getValue()));
        }
    }

    private boolean knownClient(String username, String client, Instant now) {
        Instant last = knownClients.getOrDefault(name(username), Map.of()).get(client);
        return last != null && last.plus(KNOWN_FOR).isAfter(now);
    }

    /**
     * Entries older than the window go. Removed only on a successful login, the map grew
     * with every made-up username a loop sent, until the server ran out of memory.
     */
    @Scheduled(fixedDelay = 5 * 60 * 1000)
    void removeStale() {
        Instant cutoff = clock.instant().minus(WINDOW);
        attempts.values().removeIf(entry -> entry.last().isBefore(cutoff));
        clients.removeStale();
        users.removeStale();
        Instant knownCutoff = clock.instant().minus(KNOWN_FOR);
        knownClients.values().forEach(known -> known.values().removeIf(last -> last.isBefore(knownCutoff)));
        knownClients.values().removeIf(Map::isEmpty);
    }

    /** How many usernames are being counted across addresses -- for the test. */
    int trackedUsers() {
        return users.tracked();
    }

    /** How many usernames (per address) are being counted -- for the test. */
    int tracked() {
        return attempts.size();
    }

    /** How many client addresses are being counted -- for the test. */
    int trackedClients() {
        return clients.tracked();
    }

    /** How long after this attempt the next one has to wait. */
    private static Duration wait(int count) {
        if (count < FREE) {
            return Duration.ZERO;
        }
        long seconds = STEP.toSeconds() << Math.min(count - FREE, 10);
        return Duration.ofSeconds(Math.min(seconds, CEILING.toSeconds()));
    }

    private static String key(String username, String client) {
        return name(username) + " " + client;
    }

    /**
     * The username as the throttle counts it -- cut to the length a real one can have.
     * It is the key of three maps, kept for minutes: sent megabytes long, a few dozen
     * sign-ins without an account filled the heap. No account has a longer name, so
     * everything beyond the cut is the same nobody.
     */
    private static String name(String username) {
        if (username == null) {
            return "";
        }
        String trimmed = username.trim();
        if (trimmed.length() > MAX_NAME_LENGTH) {
            trimmed = trimmed.substring(0, MAX_NAME_LENGTH);
        }
        return trimmed.toLowerCase(Locale.ROOT);
    }

    /** Twice the longest username the server accepts. */
    static final int MAX_NAME_LENGTH = 64;
}
