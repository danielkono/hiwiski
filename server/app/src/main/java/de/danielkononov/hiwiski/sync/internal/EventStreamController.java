package de.danielkononov.hiwiski.sync.internal;

import de.danielkononov.hiwiski.identity.DeviceRevoked;
import de.danielkononov.hiwiski.platform.ChangeSequence;
import de.danielkononov.hiwiski.platform.RestoreInProgress;
import java.io.IOException;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.event.EventListener;
import org.springframework.http.MediaType;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.transaction.event.TransactionalEventListener;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

/**
 * The real-time signal.
 *
 * <p><strong>The only endpoint outside the spec</strong>: a long-lived stream cannot be
 * expressed in OpenAPI, and the generators turn it into unusable signatures on both
 * sides.
 *
 * <p><strong>The signal carries no data</strong>, only the sequence number. Every signal
 * triggers a normal, share-filtered pull; a missed one cannot break anything. Batched
 * over 250 ms, heartbeat every 25 seconds.
 */
@RestController
class EventStreamController {

    private static final Logger log = LoggerFactory.getLogger(EventStreamController.class);

    /** Long enough that a wall tablet does not keep reconnecting. */
    private static final long STREAM_TIMEOUT_MILLIS = 30 * 60 * 1000L;

    private final EventTickets tickets;
    private final ChangeSequence sequence;
    private final RestoreInProgress restore;

    private final Map<UUID, SseEmitter> listeners = new ConcurrentHashMap<>();

    /** The device each stream runs on, where it has one — by stream id. */
    private final Map<UUID, UUID> devices = new ConcurrentHashMap<>();

    /** The address each stream was opened with, where it has one — by stream id. */
    private final Map<UUID, String> addresses = new ConcurrentHashMap<>();
    private final AtomicLong lastAnnounced = new AtomicLong(-1);

    EventStreamController(EventTickets tickets, ChangeSequence sequence, RestoreInProgress restore) {
        this.tickets = tickets;
        this.sequence = sequence;
        this.restore = restore;
    }

    @GetMapping(value = "/api/v1/events", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    org.springframework.http.ResponseEntity<SseEmitter> stream(@RequestParam("ticket") String ticket) {
        // No valid ticket, no stream. Before, it revealed *that* something had changed
        // -- that too is information. A plain 403 without a body: an error body cannot
        // be written as an event stream, and trying turned every refused ticket into a
        // 500 with a stack trace.
        var redeemed = tickets.redeem(ticket);
        if (redeemed.isEmpty()) {
            return org.springframework.http.ResponseEntity.status(org.springframework.http.HttpStatus.FORBIDDEN)
                    .build();
        }
        var issued = redeemed.get();

        UUID id = UUID.randomUUID();
        SseEmitter emitter = new SseEmitter(STREAM_TIMEOUT_MILLIS);
        emitter.onCompletion(() -> forget(id));
        emitter.onTimeout(() -> forget(id));
        emitter.onError(error -> forget(id));
        listeners.put(id, emitter);
        if (issued.deviceId() != null) {
            devices.put(id, issued.deviceId());
        }
        if (issued.address() != null) {
            addresses.put(id, issued.address());
        }

        // The current state right away: a client that missed something while connecting
        // catches up on it immediately.
        send(emitter, sequence.current());
        if (restore.since().isPresent()) {
            restoring(emitter, true);
        }
        return org.springframework.http.ResponseEntity.ok(emitter);
    }

    /**
     * Batched over 250 ms.
     *
     * <p>The tick reads the sequence number and sends only if it has changed. Hooking
     * into the log would be more precise, but would need an event in the write
     * transaction -- and that is exactly what the log should not have.
     */
    @Scheduled(fixedDelay = 250)
    void announce() {
        if (listeners.isEmpty()) {
            return;
        }
        long current = sequence.current();
        if (lastAnnounced.getAndSet(current) == current) {
            return;
        }
        listeners.values().forEach(emitter -> send(emitter, current));
    }

    /**
     * A signed-out device hears it at once: {@code revoked}, then the stream ends.
     *
     * <p>Before, it noticed only on its next call — and an idle tablet kept showing the
     * family's data until someone touched it. After the commit: the token is invalid by
     * then, so whatever the app does next fails as it should.
     */
    @TransactionalEventListener
    void onDeviceRevoked(DeviceRevoked revoked) {
        // A ticket fetched just before and not redeemed yet: a stream opened with it
        // would belong to a revoked device and never hear of it.
        tickets.revokeDevice(revoked.deviceId());
        devices.forEach((id, deviceId) -> {
            if (!deviceId.equals(revoked.deviceId())) {
                return;
            }
            revoke(listeners.get(id));
        });
    }

    /**
     * An address that opens nothing any more — regenerated, or its board gone: the wall
     * tablet hears {@code revoked} at once, as a signed-out device does, instead of
     * hearing of every change until its stream timed out.
     */
    @EventListener
    void onAddressEnded(EventTickets.AddressEnded ended) {
        addresses.forEach((id, address) -> {
            if (address.equals(ended.address())) {
                revoke(listeners.get(id));
            }
        });
    }

    /**
     * A backup is being restored, or is done: every app hears it at once and shows that
     * it takes no changes -- not only the one that started it.
     */
    @EventListener
    void onRestore(RestoreInProgress.Changed changed) {
        listeners.values().forEach(emitter -> restoring(emitter, changed.running()));
    }

    private void restoring(SseEmitter emitter, boolean running) {
        try {
            emitter.send(SseEmitter.event().name("restoring").data(String.valueOf(running)));
        } catch (IOException | IllegalStateException closed) {
            log.debug("event stream closed before the restore reached it");
            close(emitter);
        }
    }

    private void revoke(SseEmitter emitter) {
        if (emitter == null) {
            return;
        }
        try {
            emitter.send(SseEmitter.event().name("revoked").data("revoked"));
        } catch (IOException | IllegalStateException closed) {
            log.debug("event stream closed before the revocation reached it");
        }
        close(emitter);
    }

    private void forget(UUID id) {
        listeners.remove(id);
        devices.remove(id);
        addresses.remove(id);
    }

    /** Heartbeat every 25 seconds so intermediaries do not cut the connection. */
    @Scheduled(fixedDelay = 25_000)
    void heartbeat() {
        listeners.values().forEach(emitter -> {
            try {
                emitter.send(SseEmitter.event().comment("heartbeat"));
            } catch (IOException | IllegalStateException closed) {
                close(emitter);
            }
        });
    }

    private void send(SseEmitter emitter, long seq) {
        try {
            emitter.send(SseEmitter.event().name("seq").data(String.valueOf(seq)));
        } catch (IOException | IllegalStateException closed) {
            log.debug("event stream closed while sending");
            close(emitter);
        }
    }

    /**
     * A connection that is already gone can no longer be closed cleanly:
     * {@code complete()} then tries to write once more and throws. That is not an error
     * but a tab that was closed — so unregister and stay quiet instead of writing a
     * stack trace to the log on every heartbeat.
     */
    private void close(SseEmitter emitter) {
        listeners.entrySet().removeIf(entry -> {
            if (entry.getValue() != emitter) {
                return false;
            }
            devices.remove(entry.getKey());
            addresses.remove(entry.getKey());
            return true;
        });
        try {
            emitter.complete();
        } catch (Exception alreadyGone) {
            log.debug("event stream already gone");
        }
    }
}
