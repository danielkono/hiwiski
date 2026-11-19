package de.danielkononov.hiwiski.sync.internal;

import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Base64;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Short-lived tickets for the SSE stream.
 *
 * <p>{@code EventSource} in the browser cannot send a header, and in an earlier version the
 * endpoint was therefore the only one without authentication -- it revealed
 * <em>that</em> something had changed. Instead, the app requests a ticket beforehand and
 * appends it as a query parameter.
 *
 * <p>In memory and not in the database: 60 seconds lifetime, redeemable once. A restart
 * invalidates them, and that is right -- the stream breaks off anyway.
 */
@Component
class EventTickets implements de.danielkononov.hiwiski.sync.StreamTickets {

    private static final Duration LIFETIME = Duration.ofSeconds(60);

    private static final SecureRandom RANDOM = new SecureRandom();

    /** @param address what a reader without a device opened it with, or {@code null} */
    record Issued(UUID memberId, UUID deviceId, String address, Instant expiresAt) {}

    /** An address that opens nothing any more: the streams opened with it end. */
    record AddressEnded(String address) {}

    private final Map<String, Issued> tickets = new ConcurrentHashMap<>();
    private final ApplicationEventPublisher events;

    EventTickets(ApplicationEventPublisher events) {
        this.events = events;
    }

    @Override
    public Ticket issue(UUID memberId, UUID deviceId) {
        return issue(memberId, deviceId, null);
    }

    @Override
    public Ticket issueForAddress(UUID memberId, String address) {
        return issue(memberId, null, address);
    }

    private Ticket issue(UUID memberId, UUID deviceId, String address) {
        byte[] bytes = new byte[24];
        RANDOM.nextBytes(bytes);
        String value = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        Instant expiresAt = Instant.now().plus(LIFETIME);
        tickets.put(value, new Issued(memberId, deviceId, address, expiresAt));
        return new Ticket(value, expiresAt.atOffset(ZoneOffset.UTC));
    }

    @Override
    public void endAddress(String address) {
        tickets.values().removeIf(issued -> address.equals(issued.address()));
        events.publishEvent(new AddressEnded(address));
    }

    /** Redeemable once: the ticket is gone after it is read. */
    Optional<Issued> redeem(String value) {
        if (value == null) {
            return Optional.empty();
        }
        Issued issued = tickets.remove(value);
        if (issued == null || issued.expiresAt().isBefore(Instant.now())) {
            return Optional.empty();
        }
        return Optional.of(issued);
    }

    /**
     * The tickets of a device that was just signed out. Redeemed after the revocation,
     * one opened a stream for half an hour that nothing would ever close.
     */
    void revokeDevice(UUID deviceId) {
        tickets.values().removeIf(issued -> deviceId.equals(issued.deviceId()));
    }

    @Scheduled(fixedDelay = 60_000)
    void removeExpired() {
        Instant now = Instant.now();
        tickets.values().removeIf(issued -> issued.expiresAt().isBefore(now));
    }
}
