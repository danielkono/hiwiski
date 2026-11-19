package de.danielkononov.hiwiski.dashboard.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.BOARD;

import de.danielkononov.hiwiski.sync.EntityWritten;
import de.danielkononov.hiwiski.sync.StreamTickets;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import org.jooq.DSLContext;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

/**
 * The addresses wall tablets opened their streams with, by board — so that the streams of
 * an address end when it does.
 *
 * <p>"Regenerate address" kills the old one for loading the board, and a stream opened
 * with it used to keep hearing of every change until it timed out half an hour later. A
 * board's write is the moment its address can change; the board's token is read then,
 * and every address handed out for it that is no longer its token is ended.
 *
 * <p>In memory, like the tickets: a restart ends every stream anyway.
 */
@Component
class DashboardAddresses {

    private final DSLContext db;
    private final StreamTickets tickets;

    private final Map<UUID, Set<String>> handedOut = new ConcurrentHashMap<>();

    DashboardAddresses(DSLContext db, StreamTickets tickets) {
        this.db = db;
        this.tickets = tickets;
    }

    /** A ticket for the wall tablet at [address], in the board owner's name. */
    StreamTickets.Ticket ticket(UUID boardId, UUID ownerId, String address) {
        handedOut.computeIfAbsent(boardId, id -> ConcurrentHashMap.newKeySet()).add(address);
        return tickets.issueForAddress(ownerId, address);
    }

    @ApplicationModuleListener
    void onEntityWritten(EntityWritten event) {
        if (!DashboardSyncTypes.BOARD_TYPE.equals(event.entityType())) {
            return;
        }
        Set<String> addresses = handedOut.get(event.entityId());
        if (addresses == null) {
            return;
        }
        // Gone with the board, or replaced by a new one: what is not the token now ends.
        String current = db.select(BOARD.TOKEN)
                .from(BOARD)
                .where(BOARD.ID.eq(event.entityId()))
                .and(BOARD.DELETED_AT.isNull())
                .fetchOne(BOARD.TOKEN);
        addresses.removeIf(address -> {
            if (address.equals(current)) {
                return false;
            }
            tickets.endAddress(address);
            return true;
        });
        if (addresses.isEmpty()) {
            handedOut.remove(event.entityId(), addresses);
        }
    }
}
