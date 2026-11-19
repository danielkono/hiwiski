package de.danielkononov.hiwiski.sync.internal;

import de.danielkononov.hiwiski.api.model.ChangeEnvelope;
import de.danielkononov.hiwiski.api.model.PullResponse;
import de.danielkononov.hiwiski.api.model.SyncOp;
import de.danielkononov.hiwiski.identity.CurrentUser;
import de.danielkononov.hiwiski.platform.ChangeSequence;
import de.danielkononov.hiwiski.platform.InstanceSettings;
import de.danielkononov.hiwiski.platform.SettingKey;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.sync.ChangeVisibility;
import de.danielkononov.hiwiski.sync.SyncRegistry;
import de.danielkononov.hiwiski.sync.SyncType;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * The read path: the delta since the device's position.
 *
 * <p>A monotonically increasing sequence number per family is more robust than
 * timestamps across device clocks.
 */
@Service
class PullService {

    /** No more than this fits in one response -- the client then pulls again. */
    private static final int MAX_LIMIT = 1000;

    private static final int DEFAULT_LIMIT = 500;

    private final ChangeLogRepository changeLog;
    private final ChangeVisibility visibility;
    private final ChangeSequence sequence;
    private final InstanceSettings settings;
    private final DeviceProgress progress;
    private final EntityRepository entities;
    private final SyncRegistry registry;

    PullService(
            ChangeLogRepository changeLog,
            ChangeVisibility visibility,
            ChangeSequence sequence,
            InstanceSettings settings,
            DeviceProgress progress,
            EntityRepository entities,
            SyncRegistry registry) {
        this.changeLog = changeLog;
        this.visibility = visibility;
        this.sequence = sequence;
        this.settings = settings;
        this.progress = progress;
        this.entities = entities;
        this.registry = registry;
    }

    @Transactional
    PullResponse pull(long lastSeq, UUID deviceId, Integer pendingCount, Integer limit, CurrentUser.Principal principal) {
        // The device reports its position along with the pull. Only that way can the
        // device list show "3 changes waiting - offline for 12 days".
        progress.record(deviceId, lastSeq, pendingCount);

        UUID instanceId = settings.find(SettingKey.INSTANCE_ID).map(UUID::fromString).orElse(null);
        long latest = sequence.current();

        if (needsResync(lastSeq)) {
            // The client first tries to push its outbox; whatever is rejected ends up in
            // a visible list to copy from, instead of silently disappearing.
            PullResponse response = new PullResponse(List.of(), latest, false, instanceId, true);
            return response;
        }

        int pageSize = Math.min(limit == null ? DEFAULT_LIMIT : Math.max(1, limit), MAX_LIMIT);
        var entries = changeLog.since(lastSeq, visibility.visibleTo(principal.memberId()), pageSize + 1);

        boolean hasMore = entries.size() > pageSize;
        if (hasMore) {
            entries = entries.subList(0, pageSize);
        }

        // The owner is not in the log; one query per type and page fetches it.
        Map<UUID, UUID> owners = new java.util.HashMap<>();
        entries.stream()
                .filter(entry -> "upsert".equals(entry.op()))
                .collect(java.util.stream.Collectors.groupingBy(
                        entry -> entry.entityType(),
                        java.util.stream.Collectors.mapping(entry -> entry.entityId(), java.util.stream.Collectors.toSet())))
                .forEach((entityType, ids) -> registry.find(entityType)
                        .ifPresent(type -> owners.putAll(entities.ownersOf(type, ids))));

        List<ChangeEnvelope> changes = new ArrayList<>(entries.size());
        for (var entry : entries) {
            ChangeEnvelope envelope = new ChangeEnvelope(
                    entry.seq(),
                    entry.entityType(),
                    entry.entityId(),
                    op(entry.op()),
                    entry.entityVersion());
            envelope.setContainerType(entry.containerType());
            envelope.setContainerId(entry.containerId());
            envelope.setEntityKey(entry.entityKey());
            if ("upsert".equals(entry.op())) {
                envelope.setOwnerId(owners.get(entry.entityId()));
            }
            envelope.setFields(withoutSecrets(
                    entry.entityType(), entry.fields(), envelope.getOwnerId(), principal.memberId()));
            changes.add(envelope);
        }

        // `latestSeq` is the position of the last delivered entry, not the server's:
        // otherwise the client would skip everything this page could no longer hold.
        long deliveredUpTo = changes.isEmpty() ? lastSeq : changes.getLast().getSeq();
        if (!hasMore) {
            // Nothing more for this reader up to where the scan went: the position moves
            // there even when nothing was visible. Otherwise a member who sees one quiet
            // list stood still while the family wrote, until retention cleaned up past
            // that point and forced a full resync, although nothing was missed.
            // Everything up to `latest` was committed when it was read: numbers are
            // drawn under a lock held until commit.
            deliveredUpTo = Math.max(deliveredUpTo, latest);
        }
        return new PullResponse(changes, deliveredUpTo, hasMore, instanceId, false);
    }

    /**
     * The snapshot: the state instead of the history.
     *
     * <p>The log is cleaned up after the retention period. A fresh
     * device replaying it from 0 would then get only what someone has touched since --
     * and of that only the changed fields. The snapshot therefore reads the entity
     * tables: every live, visible item once, with all fields.
     *
     * <p>{@code latestSeq} is, on every page, the position at the start of the snapshot;
     * it travels along in the cursor. From there on it continues with the log. Whatever
     * happened during the snapshot thus comes a second time -- in log order, and so with
     * the right outcome.
     */
    @Transactional
    PullResponse snapshot(
            String cursor, UUID deviceId, Integer pendingCount, Integer limit, CurrentUser.Principal principal) {
        progress.record(deviceId, 0, pendingCount);
        UUID instanceId = settings.find(SettingKey.INSTANCE_ID).map(UUID::fromString).orElse(null);
        int pageSize = Math.min(limit == null ? DEFAULT_LIMIT : Math.max(1, limit), MAX_LIMIT);

        Cursor position = cursor == null || cursor.isEmpty()
                ? new Cursor(sequence.current(), null, null)
                : Cursor.parse(cursor);

        List<SyncType> types = containersFirst();
        int start = 0;
        if (position.entityType() != null) {
            start = -1;
            for (int i = 0; i < types.size(); i++) {
                if (types.get(i).entityType().equals(position.entityType())) {
                    start = i;
                }
            }
            if (start < 0) {
                throw HiwiskiException.invalid("sync.invalid_cursor", "snapshotCursor", cursor);
            }
        }

        List<ChangeEnvelope> changes = new ArrayList<>(pageSize);
        UUID afterId = position.afterId();
        for (int i = start; i < types.size(); i++) {
            SyncType type = types.get(i);
            var condition = visibility.itemVisibleTo(
                    principal.memberId(), type.entityType(), EntityRepository.idColumn(type));
            // One more than there is room for: that tells whether this type continues.
            int room = pageSize - changes.size();
            var page = entities.livePage(type, condition, afterId, room + 1);
            for (var item : page.subList(0, Math.min(room, page.size()))) {
                var envelope = envelope(type, item);
                envelope.setFields(withoutSecrets(
                        type.entityType(), envelope.getFields(), item.ownerId(), principal.memberId()));
                changes.add(envelope);
            }
            if (page.size() > room) {
                // The page is full, in the middle of this type.
                var next = new Cursor(position.seq(), type.entityType(), changes.getLast().getEntityId());
                return snapshotPage(changes, position.seq(), instanceId, next);
            }
            afterId = null;
            if (changes.size() == pageSize && i + 1 < types.size()) {
                // Full, exactly at a type boundary: the next one starts from the top.
                var next = new Cursor(position.seq(), types.get(i + 1).entityType(), null);
                return snapshotPage(changes, position.seq(), instanceId, next);
            }
        }
        return snapshotPage(changes, position.seq(), instanceId, null);
    }

    private static PullResponse snapshotPage(
            List<ChangeEnvelope> changes, long seq, UUID instanceId, Cursor next) {
        PullResponse response = new PullResponse(changes, seq, next != null, instanceId, false);
        if (next != null) {
            response.setSnapshotCursor(next.format());
        }
        return response;
    }

    /** For {@link de.danielkononov.hiwiski.sync.VisibleItems}: the snapshot's reading, filtered. */
    List<ChangeEnvelope> visibleTo(UUID memberId, SyncType type, org.jooq.Condition filter, int limit) {
        var condition = visibility
                .itemVisibleTo(memberId, type.entityType(), EntityRepository.idColumn(type))
                .and(filter);
        return entities.livePage(type, condition, null, limit).stream()
                .map(item -> envelope(type, item))
                .toList();
    }

    /**
     * The fields without those only the owner may read (a board's or feed's token): a
     * share of the item must never hand over a session of its owner.
     */
    private Map<String, Object> withoutSecrets(
            String entityType, Map<String, Object> fields, UUID ownerId, UUID reader) {
        if (fields == null || reader.equals(ownerId)) {
            return fields;
        }
        var secret = registry.find(entityType).map(SyncType::secretFields).orElse(java.util.Set.of());
        if (secret.isEmpty() || java.util.Collections.disjoint(secret, fields.keySet())) {
            return fields;
        }
        Map<String, Object> visible = new java.util.LinkedHashMap<>(fields);
        visible.keySet().removeAll(secret);
        return visible;
    }

    private static ChangeEnvelope envelope(SyncType type, EntityRepository.Live item) {
        // The version is the sequence number of the last write -- it serves as `seq`
        // just as well, and it never lies behind the snapshot's position.
        ChangeEnvelope envelope =
                new ChangeEnvelope(item.version(), type.entityType(), item.id(), SyncOp.UPSERT, item.version());
        type.container().ifPresent(container -> {
            envelope.setContainerType(container.type());
            envelope.setContainerId(item.containerId());
        });
        envelope.setFields(item.fields());
        envelope.setEntityKey(item.entityKey());
        envelope.setOwnerId(item.ownerId());
        return envelope;
    }

    /**
     * Containers before their content: the list before the task, the task before its
     * occurrence. A client with foreign keys would otherwise not accept the content.
     */
    private List<SyncType> containersFirst() {
        return registry.all().stream()
                .sorted(Comparator.comparingInt(this::depth).thenComparing(SyncType::entityType))
                .toList();
    }

    private int depth(SyncType type) {
        int depth = 0;
        SyncType current = type;
        while (current != null && current.container().isPresent() && depth < 10) {
            depth++;
            current = registry.find(current.container().get().type()).orElse(null);
        }
        return depth;
    }

    /**
     * Where the snapshot stands: {@code <seq>:<type>:<last ID>}.
     *
     * <p>Opaque to the client -- it passes it back unchanged.
     */
    private record Cursor(long seq, String entityType, UUID afterId) {

        String format() {
            return seq + ":" + entityType + ":" + (afterId == null ? "" : afterId);
        }

        static Cursor parse(String value) {
            String[] parts = value.split(":", -1);
            try {
                if (parts.length != 3 || parts[1].isEmpty()) {
                    throw new IllegalArgumentException(value);
                }
                return new Cursor(
                        Long.parseLong(parts[0]),
                        parts[1],
                        parts[2].isEmpty() ? null : UUID.fromString(parts[2]));
            } catch (IllegalArgumentException e) {
                throw HiwiskiException.invalid("sync.invalid_cursor", "snapshotCursor", value);
            }
        }
    }

    /**
     * If {@code lastSeq} lies before the oldest log entry, the client is missing what
     * has been cleaned up in the meantime.
     *
     * <p>{@code lastSeq == 0} is exempt: a fresh device has not missed anything yet, it
     * just has not seen anything yet.
     */
    private boolean needsResync(long lastSeq) {
        if (lastSeq == 0) {
            return false;
        }
        return changeLog.oldestSeq().map(oldest -> lastSeq < oldest - 1).orElse(false);
    }

    private static SyncOp op(String value) {
        for (SyncOp candidate : SyncOp.values()) {
            if (candidate.getValue().equals(value)) {
                return candidate;
            }
        }
        return SyncOp.UPSERT;
    }
}
