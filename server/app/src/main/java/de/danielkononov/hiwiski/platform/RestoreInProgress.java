package de.danielkononov.hiwiski.platform;

import java.time.Instant;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicReference;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Component;

/**
 * A backup is being restored right now.
 *
 * <p>Until it is done the instance is read-only for everyone: a change written while
 * the tables are swapped would land in the state about to be replaced, or not at all.
 * The handshake says so, so that every app -- the one that started it, restarted, and
 * every other -- shows that it waits instead of failing at the next save.
 *
 * <p>In memory, not in the database: a server that stops mid-restore has no restore
 * running when it starts again -- the instance is as it was before.
 */
@Component
public class RestoreInProgress {

    private final AtomicReference<Instant> since = new AtomicReference<>();
    private final ApplicationEventPublisher events;

    public RestoreInProgress(ApplicationEventPublisher events) {
        this.events = events;
    }

    /**
     * A restore begins or ends -- for the event stream, which tells every connected
     * app at once instead of at its next start or its next refused change.
     */
    public record Changed(boolean running) {}

    public void begin() {
        since.set(Instant.now());
        events.publishEvent(new Changed(true));
    }

    public void end() {
        if (since.getAndSet(null) != null) {
            events.publishEvent(new Changed(false));
        }
    }

    public Optional<Instant> since() {
        return Optional.ofNullable(since.get());
    }
}
