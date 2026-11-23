package de.danielkononov.hiwiski.sync.internal;

import de.danielkononov.hiwiski.platform.ChangeSequence;
import de.danielkononov.hiwiski.sync.EntityWritten;
import de.danielkononov.hiwiski.sync.SyncRegistry;
import de.danielkononov.hiwiski.sync.SyncType;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * What disappears along with a deleted item -- and what in turn disappears with that.
 *
 * <p>One place for a push and a server write: the server's own deletes (a calendar
 * subscription removing events) used to delete only the item itself, and its children
 * stayed alive.
 */
@Component
class Cascade {

    private final SyncRegistry registry;
    private final EntityRepository entities;
    private final ChangeLogRepository changeLog;
    private final ChangeSequence sequence;
    private final ApplicationEventPublisher events;

    Cascade(
            SyncRegistry registry,
            EntityRepository entities,
            ChangeLogRepository changeLog,
            ChangeSequence sequence,
            ApplicationEventPublisher events) {
        this.registry = registry;
        this.entities = entities;
        this.changeLog = changeLog;
        this.sequence = sequence;
        this.events = events;
    }

    /**
     * @param actor who deleted the item
     * @param device the device it came from, or {@code null} for the server
     */
    @Transactional(propagation = Propagation.MANDATORY)
    void deleteAlong(SyncType type, UUID entityId, UUID actor, UUID device) {
        Set<String> visited = new HashSet<>();
        visited.add(type.entityType() + entityId);
        deleteAlong(type, entityId, actor, device, visited);
    }

    /**
     * Whether everything that would go along with this delete may go -- asked before
     * anything is deleted, so a refusal leaves the whole tree as it was.
     *
     * @param may whether one item that goes along may be deleted
     */
    @Transactional(propagation = Propagation.MANDATORY)
    boolean allows(SyncType type, UUID entityId, java.util.function.Predicate<SyncType.Ref> may) {
        Set<String> visited = new HashSet<>();
        visited.add(type.entityType() + entityId);
        return allows(type, entityId, may, visited);
    }

    private boolean allows(
            SyncType type, UUID entityId, java.util.function.Predicate<SyncType.Ref> may, Set<String> visited) {
        for (SyncType.Ref gone : type.alsoDeleted(entityId)) {
            if (!visited.add(gone.entityType() + gone.entityId())) {
                continue;
            }
            var goneType = registry.find(gone.entityType()).orElse(null);
            if (goneType == null) {
                continue;
            }
            if (!may.test(gone) || !allows(goneType, gone.entityId(), may, visited)) {
                return false;
            }
        }
        return true;
    }

    private void deleteAlong(SyncType type, UUID entityId, UUID actor, UUID device, Set<String> visited) {
        for (SyncType.Ref gone : type.alsoDeleted(entityId)) {
            if (!visited.add(gone.entityType() + gone.entityId())) {
                continue;
            }
            var goneType = registry.find(gone.entityType()).orElse(null);
            if (goneType == null) {
                continue;
            }
            long goneSeq = sequence.next();
            entities.softDelete(goneType, gone.entityId(), goneSeq, actor);
            changeLog.append(
                    goneSeq,
                    gone.entityType(),
                    gone.entityId(),
                    null,
                    null,
                    "delete",
                    Map.of(),
                    List.of(),
                    actor,
                    device,
                    goneSeq);
            // The ones taken along too: an event that disappears with its calendar has to
            // leave the search index as well.
            events.publishEvent(new EntityWritten(gone.entityType(), gone.entityId(), actor, true, false, goneSeq));
            deleteAlong(goneType, gone.entityId(), actor, device, visited);
        }
    }
}
