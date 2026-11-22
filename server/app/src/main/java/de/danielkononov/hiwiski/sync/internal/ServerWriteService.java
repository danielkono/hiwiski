package de.danielkononov.hiwiski.sync.internal;

import de.danielkononov.hiwiski.platform.ChangeSequence;
import de.danielkononov.hiwiski.platform.EntityKeys;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.sync.ChangeVisibility;
import de.danielkononov.hiwiski.sync.ServerWrites;
import de.danielkononov.hiwiski.sync.SyncRegistry;
import de.danielkononov.hiwiski.sync.SyncType;
import de.danielkononov.hiwiski.sync.SyncField;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import de.danielkononov.hiwiski.sync.EntityWritten;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Server-side writes, through the same mechanics as a push. */
@Service
class ServerWriteService implements ServerWrites {

    private final SyncRegistry registry;
    private final EntityRepository entities;
    private final ChangeLogRepository changeLog;
    private final ChangeSequence sequence;
    private final EntityKeys entityKeys;
    private final ChangeVisibility visibility;
    private final ApplicationEventPublisher events;
    private final Cascade cascade;

    ServerWriteService(
            SyncRegistry registry,
            EntityRepository entities,
            ChangeLogRepository changeLog,
            ChangeSequence sequence,
            EntityKeys entityKeys,
            ChangeVisibility visibility,
            ApplicationEventPublisher events,
            Cascade cascade) {
        this.registry = registry;
        this.entities = entities;
        this.changeLog = changeLog;
        this.sequence = sequence;
        this.entityKeys = entityKeys;
        this.visibility = visibility;
        this.events = events;
        this.cascade = cascade;
    }

    @Override
    @Transactional
    public long upsert(
            String entityType,
            UUID entityId,
            String containerType,
            UUID containerId,
            Map<String, Object> fields,
            UUID actor) {

        SyncType type = registry.find(entityType)
                .orElseThrow(() -> HiwiskiException.invalid("sync.unknown_entity_type", "entityType", entityType));

        // The lock before the read, as in a push: read before it, the item may already
        // be stale when this write gets its turn.
        long seq = sequence.next();
        var current = entities.load(type, entityId).orElse(null);

        // Imported events get NO readable key: they belong to the source, and a holiday
        // calendar would use up five hundred numbers for something nobody cites.
        String entityKey = current != null ? current.entityKey() : null;

        // baseVersion = current version: the server writes on the state it has just
        // read, and so never collides with itself.
        var upsert = entities.partition(type, current, fields, current == null ? null : current.version());
        entities.write(type, entityId, current, upsert.accepted(), seq, actor, containerId, entityKey);

        changeLog.append(
                seq,
                entityType,
                entityId,
                containerType,
                containerId,
                "upsert",
                upsert.accepted(),
                List.copyOf(upsert.accepted().keySet()),
                actor,
                null,
                seq,
                entityKey);

        visibility.onEntityWritten(entityType, entityId, actor, current == null, Map.of());
        // Like a push: search and references follow what the server writes too --
        // otherwise imported events were never found.
        events.publishEvent(new EntityWritten(entityType, entityId, actor, false, true, seq));
        return seq;
    }

    @Override
    @Transactional
    public long delete(String entityType, UUID entityId, UUID actor) {
        SyncType type = registry.find(entityType)
                .orElseThrow(() -> HiwiskiException.invalid("sync.unknown_entity_type", "entityType", entityType));

        long seq = sequence.next();
        entities.softDelete(type, entityId, seq, actor);
        changeLog.append(
                seq,
                entityType,
                entityId,
                type.container().map(SyncType.Container::type).orElse(null),
                entities.containerOf(type, entityId).orElse(null),
                "delete",
                Map.of(),
                List.of(),
                actor,
                null,
                seq);
        // What goes with it goes here too, and search drops it -- an event the feed
        // removed used to stay a hit, and a server delete of a container left its
        // children alive.
        cascade.deleteAlong(type, entityId, actor, null);
        events.publishEvent(new EntityWritten(entityType, entityId, actor, true, true));
        return seq;
    }

    @Override
    @Transactional
    public long restore(String entityType, UUID entityId, UUID targetContainerId, UUID actor) {
        SyncType type = registry.find(entityType)
                .orElseThrow(() -> HiwiskiException.invalid("sync.unknown_entity_type", "entityType", entityType));
        long seq = sequence.next();
        var deleted = entities.load(type, entityId)
                .filter(EntityRepository.Snapshot::deleted)
                .orElseThrow(() -> HiwiskiException.notFound("sync.entity_not_found", "entityId", entityId));

        Map<String, Object> fields = new LinkedHashMap<>(deleted.fields());
        if (targetContainerId != null) {
            moveInto(type, entityId, targetContainerId, actor, fields);
        }

        var deletedAt = entities.deletedAt(type, entityId).orElse(null);
        entities.restore(type, entityId, targetContainerId, seq, actor);
        changeLog.append(
                seq,
                entityType,
                entityId,
                type.container().map(SyncType.Container::type).orElse(null),
                entities.containerOf(type, entityId).orElse(null),
                "upsert",
                fields,
                List.copyOf(fields.keySet()),
                actor,
                null,
                seq,
                deleted.entityKey());

        // Not a creation: devices that saw the item go have only its tombstone and need it
        // in full again.
        visibility.onEntityWritten(entityType, entityId, actor, false, Map.of());
        // Search and references dropped the item on its delete; they take it back the
        // same way they would take any other change.
        events.publishEvent(new EntityWritten(entityType, entityId, actor, false, false, seq));

        // What went with it and has no way back of its own -- each a change in the log
        // with all its fields, like the item.
        if (deletedAt != null) {
            for (SyncType.Ref along : type.alsoRestored(entityId, deletedAt)) {
                var alongType = registry.find(along.entityType()).orElse(null);
                boolean stillDeleted = alongType != null
                        && entities.load(alongType, along.entityId())
                                .filter(EntityRepository.Snapshot::deleted)
                                .isPresent();
                if (stillDeleted) {
                    restore(along.entityType(), along.entityId(), null, actor);
                }
            }
        }
        return seq;
    }

    /**
     * Checks a restore's target the way a push checks a new item's container, and puts
     * it into the fields where the container is a field of its own (a page's parent).
     */
    @SuppressWarnings("unchecked")
    private void moveInto(SyncType type, UUID entityId, UUID target, UUID actor, Map<String, Object> fields) {
        SyncType.Container container = type.container()
                .orElseThrow(() -> HiwiskiException.invalid("sync.no_container", "entityType", type.entityType()));
        boolean live = registry.find(container.type())
                .flatMap(containerType -> entities.load(containerType, target))
                .filter(candidate -> !candidate.deleted())
                .isPresent();
        if (!live || !visibility.mayPlaceIn(actor, type.entityType(), target)) {
            throw HiwiskiException.notFound("sync.container_not_found", "containerId", target);
        }
        type.fields().stream()
                .filter(field -> field.column().equals(container.column()))
                .findFirst()
                .ifPresent(field -> fields.put(field.name(), ((SyncField<Object>) field).encode().apply(target)));
        // An archived list stays read-only, and a board takes no repeating task --
        // whichever way an item arrives.
        type.refusal(entityId, true, target, fields).ifPresent(code -> {
            throw HiwiskiException.invalid(code, "containerId", target);
        });
    }
}
