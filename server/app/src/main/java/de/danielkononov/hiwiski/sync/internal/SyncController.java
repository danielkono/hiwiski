package de.danielkononov.hiwiski.sync.internal;

import de.danielkononov.hiwiski.api.SyncApi;
import de.danielkononov.hiwiski.api.model.EventTicket;
import de.danielkononov.hiwiski.api.model.PullRequest;
import de.danielkononov.hiwiski.api.model.PullResponse;
import de.danielkononov.hiwiski.api.model.PushRequest;
import de.danielkononov.hiwiski.api.model.PushResponse;
import de.danielkononov.hiwiski.identity.CurrentUser;
import de.danielkononov.hiwiski.platform.ChangeSequence;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

@RestController
class SyncController implements SyncApi {

    private final PullService pull;
    private final PushService push;
    private final ChangeSequence sequence;
    private final EventTickets tickets;

    SyncController(PullService pull, PushService push, ChangeSequence sequence, EventTickets tickets) {
        this.pull = pull;
        this.push = push;
        this.sequence = sequence;
        this.tickets = tickets;
    }

    /**
     * The device whose position is recorded is the one the token belongs to. The
     * request's {@code deviceId} is not trusted: any member could have written another
     * device's position, pending count and "last seen", and made a lost phone look
     * synced just now.
     */
    @Override
    public ResponseEntity<PullResponse> pull(PullRequest request) {
        var principal = CurrentUser.require();
        if (Boolean.TRUE.equals(request.getSnapshot())) {
            return ResponseEntity.ok(pull.snapshot(
                    request.getSnapshotCursor(),
                    principal.deviceId(),
                    request.getPendingCount(),
                    request.getLimit(),
                    principal));
        }
        return ResponseEntity.ok(pull.pull(
                request.getLastSeq(),
                principal.deviceId(),
                request.getPendingCount(),
                request.getLimit(),
                principal));
    }

    @Override
    public ResponseEntity<PushResponse> push(PushRequest request) {
        var principal = CurrentUser.require();
        var results = push.apply(request.getMutations(), principal);
        return ResponseEntity.ok(new PushResponse(results, sequence.current()));
    }

    @Override
    public ResponseEntity<EventTicket> createEventTicket() {
        var principal = CurrentUser.require();
        var issued = tickets.issue(principal.memberId(), principal.deviceId());
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(new EventTicket(issued.value(), issued.expiresAt()));
    }
}
