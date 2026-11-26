package de.danielkononov.hiwiski.sync.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.DEVICE;
import static de.danielkononov.hiwiski.db.generated.Tables.PROCESSED_MUTATION;

import de.danielkononov.hiwiski.api.model.Mutation;
import de.danielkononov.hiwiski.api.model.MutationResult;
import de.danielkononov.hiwiski.api.model.MutationStatus;
import de.danielkononov.hiwiski.identity.CurrentUser;
import de.danielkononov.hiwiski.platform.ChangeSequence;
import de.danielkononov.hiwiski.platform.EntityKeys;
import de.danielkononov.hiwiski.sync.ChangeVisibility;
import de.danielkononov.hiwiski.sync.SyncRegistry;
import de.danielkononov.hiwiski.sync.SyncType;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.jooq.DSLContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Applies <strong>one</strong> mutation, in its own transaction.
 *
 * <p>Per mutation, not per request: otherwise a rejected one would drag the already
 * accepted ones down with it, and the client would get a result that does not match
 * what is on the server.
 *
 * <p>A bean of its own and not a method in {@code PushService}: a call within the same
 * class bypasses the proxy, and {@code @Transactional} would have no effect. That is
 * exactly what the first run failed on -- the sequence counter requires a running
 * transaction and got none.
 */
@Service
class MutationApplier {

    private static final Logger log = LoggerFactory.getLogger(MutationApplier.class);

    private final SyncRegistry registry;
    private final EntityRepository entities;
    private final ChangeLogRepository changeLog;
    private final ChangeSequence sequence;
    private final EntityKeys entityKeys;
    private final ChangeVisibility visibility;
    private final DSLContext db;
    private final SyncJson json;
    private final org.springframework.context.ApplicationEventPublisher events;
    private final Cascade cascade;
    private final ServerWriteService serverWrites;

    MutationApplier(
            SyncRegistry registry,
            EntityRepository entities,
            ChangeLogRepository changeLog,
            ChangeSequence sequence,
            EntityKeys entityKeys,
            ChangeVisibility visibility,
            DSLContext db,
            SyncJson json,
            org.springframework.context.ApplicationEventPublisher events,
            Cascade cascade,
            ServerWriteService serverWrites) {
        this.registry = registry;
        this.entities = entities;
        this.changeLog = changeLog;
        this.sequence = sequence;
        this.entityKeys = entityKeys;
        this.visibility = visibility;
        this.db = db;
        this.json = json;
        this.events = events;
        this.cascade = cascade;
        this.serverWrites = serverWrites;
    }

    /**
     * One mutation.
     *
     * <p>Everything happens under the change sequence's row lock, which writers take in
     * turn -- the idempotency check included. Inside the transaction alone is not
     * enough: a device that timed out and resent while the first request still ran
     * would find no processed mutation in either request, and the second would apply it
     * again instead of answering {@code duplicate}. Under the lock it waits for the
     * first to commit and then finds it.
     */
    @Transactional
    MutationResult applyOne(Mutation mutation, CurrentUser.Principal principal) {
        // A refused or repeated mutation uses the number up; the log has gaps anyway.
        long seq = sequence.next();

        Optional<MutationResult> known = alreadyProcessed(mutation, principal);
        if (known.isPresent()) {
            return known.get();
        }

        MutationResult result = compute(mutation, principal, seq);
        remember(mutation, principal, result);
        return result;
    }

    private MutationResult compute(Mutation mutation, CurrentUser.Principal principal, long seq) {
        SyncType type = registry.find(mutation.getEntityType()).orElse(null);
        if (type == null) {
            // A newer client against an older server. Not a crash, but a rejection the
            // user sees.
            log.info("rejecting unknown entity type {}", mutation.getEntityType());
            return rejected(mutation, "sync.unknown_entity_type");
        }

        // The item is read under the lock `applyOne` took: only a read after it sees
        // what the writer before committed. Read before, two pushes on the same field
        // both pass the field check, and the second overwrites the first without a
        // conflict.
        UUID entityId = mutation.getEntityId();
        var current = entities.load(type, entityId).orElse(null);
        Optional<UUID> stored = entities.containerOf(type, entityId);
        Optional<Optional<UUID>> placed = placedIn(type, mutation.getFields());
        // The container is what gets written, not what the envelope claims: an existing
        // item only moves through its container field, and a new one lands where that
        // field says if it carries one. Checking anything else would check the wrong list.
        UUID containerId = placed.isPresent()
                ? placed.get().orElse(null)
                : stored.isPresent() || current != null ? stored.orElse(null) : mutation.getContainerId();

        // Deleting an item one cannot see answers like deleting one that does not exist:
        // "applied", with nothing done. A refusal told whoever guessed or kept an id that
        // the item is there (even existence is information).
        if ("delete".equals(mutation.getOp().getValue())
                && current != null
                && !visibility.maySee(principal.memberId(), type.entityType(), entityId)) {
            return applied(mutation, seq, null);
        }

        String containerType = type.container()
                .map(SyncType.Container::type)
                .or(() -> type.carrierType(mutation.getFields()))
                .orElse(null);
        if (!visibility.mayWrite(principal.memberId(), type.entityType(), entityId, containerType, containerId)) {
            // The client is never the authority: offline, it may optimistically allow
            // what it may do as far as it last knew.
            return rejected(mutation, "access.denied");
        }
        // A move hands the item to the target's audience, so it needs what a new item
        // there needs. Access to the item itself says nothing about the target.
        boolean moves = current != null
                && placed.isPresent()
                && !java.util.Objects.equals(containerId, stored.orElse(null));
        // And it is the owner's: whoever may write within a container may not take
        // someone else's item out of it -- into their own page or calendar, which
        // re-shares it with whoever sees that one, or to the root, which hides it from
        // everyone else. Both change who sees it, which *write* does not allow.
        if (moves && !principal.memberId().equals(current.ownerId())) {
            return rejected(mutation, "access.denied");
        }
        if (moves && !visibility.mayPlaceIn(principal.memberId(), type.entityType(), containerId)) {
            return rejected(mutation, "access.denied");
        }
        // Deleting needs more than getting through the gate: *check off* passes it to
        // tick a box, and "no deleting" is part of that level.
        if ("delete".equals(mutation.getOp().getValue())
                && current != null
                && !visibility.mayDelete(principal.memberId(), type.entityType(), entityId)) {
            return rejected(mutation, "access.denied");
        }

        // An upsert on a deleted item brings it back -- which is a restore, so it needs
        // what deleting it needs. Otherwise *check off* undeleted a task by ticking it.
        if (current != null
                && current.deleted()
                && !"delete".equals(mutation.getOp().getValue())
                && !visibility.mayDelete(principal.memberId(), type.entityType(), entityId)) {
            return rejected(mutation, "sync.entity_deleted");
        }

        // A token is the owner's: anyone else writing it is refused outright. As a field
        // conflict, the answer would carry the server's value -- the token itself.
        if (current != null
                && !principal.memberId().equals(current.ownerId())
                && mutation.getFields() != null
                && !java.util.Collections.disjoint(type.secretFields(), mutation.getFields().keySet())) {
            return rejected(mutation, "access.denied");
        }

        // State before access: an archived item is read-only for its owner too.
        if (!"delete".equals(mutation.getOp().getValue())) {
            Optional<String> refusal = type.refusal(entityId, current != null, containerId, mutation.getFields());
            if (refusal.isPresent()) {
                return rejected(mutation, refusal.get());
            }
        }

        if ("delete".equals(mutation.getOp().getValue())) {
            if (current == null) {
                // Already gone means arrived. An error here would be a trap: the client
                // would block the chain although everything is fine.
                return applied(mutation, seq, null);
            }
            if (current.deleted()) {
                // Deleted already, by another device or an earlier attempt: arrived as
                // well. Deleting again would restart the trash's clock, name someone else
                // as the one who deleted it, and delete and log every child once more.
                return applied(mutation, current.version(), current.entityKey());
            }
            // What goes along has to be the member's to delete as well: the owner of a
            // list takes every task in it along; a writer does not take along a subpage
            // shared with others only.
            if (!cascade.allows(type, entityId, gone -> visibility.mayDeleteAlong(
                    principal.memberId(), type.entityType(), entityId, gone.entityType(), gone.entityId()))) {
                return rejected(mutation, "access.denied");
            }
            entities.softDelete(type, entityId, seq, principal.memberId());
            changeLog.append(
                    seq,
                    type.entityType(),
                    entityId,
                    type.container().map(SyncType.Container::type).orElse(null),
                    containerId,
                    "delete",
                    Map.of(),
                    List.of(),
                    principal.memberId(),
                    principal.deviceId(),
                    seq);

            cascade.deleteAlong(type, entityId, principal.memberId(), principal.deviceId());

            // **A delete is a change too.** Without this event the search index would
            // stay as it is and find something that no longer exists -- and the
            // references would keep pointing to an item that is gone.
            events.publishEvent(new de.danielkononov.hiwiski.sync.EntityWritten(
                    type.entityType(), entityId, principal.memberId(), true, false, seq));
            return applied(mutation, seq, null);
        }

        // The readable key is assigned EXACTLY ONCE, on the first sync to the server.
        // Who did it and when is the server's to say, not the client's.
        Map<String, Object> incoming = mutation.getFields() == null
                ? Map.of()
                : new LinkedHashMap<>(type.stamped(
                        principal.memberId(), java.time.OffsetDateTime.now(), mutation.getFields()));

        String entityKey = current != null
                ? current.entityKey()
                : type.keyType(incoming).map(entityKeys::next).orElse(null);

        // Fields this member may not write drop out of the mutation -- the `check off`
        // level covers the status and nothing else.
        Map<String, Object> permitted = new LinkedHashMap<>();
        List<String> forbidden = new ArrayList<>();
        incoming.forEach((field, value) -> {
            if (current == null
                    || visibility.mayWriteField(principal.memberId(), type.entityType(), entityId, field)) {
                permitted.put(field, value);
            } else {
                forbidden.add(field);
            }
        });
        if (permitted.isEmpty() && !forbidden.isEmpty()) {
            return rejected(mutation, "access.field_not_allowed");
        }

        // The last change to a field may be this device's own earlier write — then it is
        // what this mutation built on, not someone else's.
        var upsert = entities.partition(
                type,
                current,
                permitted,
                mutation.getBaseVersion(),
                position -> principal.deviceId() != null
                        && changeLog.deviceOf(position).filter(principal.deviceId()::equals).isPresent());

        // A field this member may not write is reported like one someone else changed:
        // with the server's value, so the device puts it back. Dropped silently, the
        // device would keep its own value at an up-to-date version, and no pull would
        // ever correct it -- the server never changed that field.
        List<String> refused = new ArrayList<>(upsert.rejected());
        refused.addAll(forbidden);

        if (current != null && upsert.accepted().isEmpty() && refused.isEmpty()) {
            // Nothing this server knows -- empty fields, or only ones a newer client
            // added. Nothing to write and nothing that collided: a conflict here would
            // show the user one with nothing in it.
            return applied(mutation, current.version(), entityKey);
        }
        if (current != null && upsert.accepted().isEmpty()) {
            // Nothing is left of this mutation. Writing it would mean bumping the
            // entity's version although nothing changed -- and thereby invalidating
            // every other device's `baseVersion`.
            return conflict(mutation, principal, type, entityId, current.version(), refused, entityKey);
        }

        // Read before the write clears it: what went with the item when it was deleted
        // comes back with it (ServerWriteService.restoreAlong).
        var revivedFrom = current != null && current.deleted()
                ? entities.deletedAt(type, entityId).orElse(null)
                : null;
        entities.write(
                type, entityId, current, upsert.accepted(), seq, principal.memberId(), containerId, entityKey);

        // The item's share must be in place BEFORE the next pull runs -- otherwise the
        // owner would not see their own freshly created item.
        // With what each written field held before: an assignment is the owner's only
        // for whom their own mutation adds.
        Map<String, Object> chosen = new LinkedHashMap<>();
        upsert.accepted().keySet().forEach(name -> chosen.put(name, current == null ? null : current.fields().get(name)));
        visibility.onEntityWritten(type.entityType(), entityId, principal.memberId(), current == null, chosen);
        // Afterwards, not instead: visibility has to be right in the same transaction,
        // updating references and search rows does not.
        events.publishEvent(new de.danielkononov.hiwiski.sync.EntityWritten(
                type.entityType(), entityId, principal.memberId(), false, false, seq));

        changeLog.append(
                seq,
                type.entityType(),
                entityId,
                type.container().map(SyncType.Container::type).orElse(null),
                containerId,
                "upsert",
                upsert.accepted(),
                List.copyOf(upsert.accepted().keySet()),
                principal.memberId(),
                principal.deviceId(),
                seq,
                entityKey);

        // After the item's own entry: a pinboard's elements need their page alive.
        if (revivedFrom != null) {
            serverWrites.restoreAlong(type, entityId, revivedFrom, principal.memberId());
        }

        if (refused.isEmpty()) {
            return applied(mutation, seq, entityKey);
        }

        return conflict(mutation, principal, type, entityId, seq, refused, entityKey);
    }

    /**
     * The container the mutation's own fields put the item in -- for the types whose
     * container column is also a synced field, such as a page's {@code parentId}.
     *
     * @return empty if the mutation does not set it; otherwise the target, which may be
     *     none
     */
    private static Optional<Optional<UUID>> placedIn(SyncType type, Map<String, Object> fields) {
        if (fields == null) {
            return Optional.empty();
        }
        return type.container()
                .flatMap(container -> type.fields().stream()
                        .filter(field -> field.column().equals(container.column()))
                        .filter(field -> fields.containsKey(field.name()))
                        .findFirst()
                        .map(field -> Optional.ofNullable((UUID) field.decode().apply(fields.get(field.name())))));
    }

    /**
     * If at least one field was discarded, the answer is {@code conflict} and carries
     * the current server state.
     *
     * <p>A conflict is <strong>always</strong> shown -- in an earlier version it silently discarded
     * the change, and on two of four screens there was not even a banner. That is the
     * worst kind of bug: one nobody notices.
     */
    private MutationResult conflict(
            Mutation mutation,
            CurrentUser.Principal principal,
            SyncType type,
            UUID entityId,
            long version,
            List<String> rejectedFields,
            String entityKey) {
        Map<String, Object> serverValues = new LinkedHashMap<>();
        entities.load(type, entityId)
                .ifPresent(after -> rejectedFields.forEach(name -> serverValues.put(name, after.fields().get(name))));

        // The losing version is not lost: whoever wants to keep it listens here (for the
        // wiki text, the conflict revision).
        Map<String, Object> fields = mutation.getFields() == null ? Map.of() : mutation.getFields();
        Map<String, Object> rejectedValues = new LinkedHashMap<>();
        rejectedFields.forEach(name -> rejectedValues.put(name, fields.get(name)));
        events.publishEvent(new de.danielkononov.hiwiski.sync.FieldsRejected(
                type.entityType(), entityId, principal.memberId(), rejectedValues, new LinkedHashMap<>(fields)));

        // What both sides started from — for the conflict view next to the two versions.
        Map<String, Object> baseValues = new LinkedHashMap<>();
        if (mutation.getBaseVersion() != null) {
            rejectedFields.forEach(name -> changeLog
                    .valueAt(type.entityType(), entityId, name, mutation.getBaseVersion())
                    .ifPresent(entry -> baseValues.put(name, entry.getValue())));
        }

        MutationResult result = new MutationResult(mutation.getMutationId(), MutationStatus.CONFLICT);
        result.setEntityId(mutation.getEntityId());
        result.setVersion(version);
        result.setEntityKey(entityKey);
        result.setConflictFields(rejectedFields);
        result.setServerFields(serverValues);
        result.setBaseFields(baseValues);
        return result;
    }

    private static MutationResult applied(Mutation mutation, long seq, String entityKey) {
        MutationResult result = new MutationResult(mutation.getMutationId(), MutationStatus.APPLIED);
        result.setEntityId(mutation.getEntityId());
        result.setVersion(seq);
        result.setEntityKey(entityKey);
        return result;
    }

    private static MutationResult rejected(Mutation mutation, String code) {
        MutationResult result = new MutationResult(mutation.getMutationId(), MutationStatus.REJECTED);
        result.setEntityId(mutation.getEntityId());
        result.setCode(code);
        return result;
    }

    /**
     * The answer to a mutation already processed: what it got the first time.
     *
     * <p>Only an applied one is {@code duplicate}. A rejection is a rejection again, with
     * its code, and a conflict a conflict with today's server values: "Try again" resends
     * a rejected entry under its mutation id, and answered {@code duplicate} the app took
     * it for success, dropped it and kept a value the server never took (the
     * worst kind of bug, one nobody notices).
     *
     * <p><strong>An answer belongs to the member who sent the mutation and to the item
     * it was about.</strong> The stored answer used to be looked up by the id alone and
     * the conflict's values loaded for whatever item the resent mutation named: a member
     * resent one of their own conflicts under someone else's page id and got that page's
     * text, or a board's address, past every visibility check. And a member who sent
     * another member's id got that member's answer while their own change was dropped.
     * A resend that names another item, or comes from another member, is refused.
     */
    private Optional<MutationResult> alreadyProcessed(Mutation mutation, CurrentUser.Principal principal) {
        UUID mutationId = mutation.getMutationId();
        var record = db.select(PROCESSED_MUTATION.RESULT, PROCESSED_MUTATION.RESPONSE, PROCESSED_MUTATION.DEVICE_ID)
                .from(PROCESSED_MUTATION)
                .where(PROCESSED_MUTATION.MUTATION_ID.eq(mutationId))
                .fetchOne();
        if (record == null) {
            return Optional.empty();
        }
        Map<String, Object> stored = json.read(record.value2());
        if (!sameSender(stored, record.value3(), principal) || !sameItem(stored, mutation)) {
            return Optional.of(rejected(mutation, MUTATION_ID_REUSED));
        }
        MutationStatus status = switch (record.value1()) {
            case "rejected" -> MutationStatus.REJECTED;
            case "conflict" -> MutationStatus.CONFLICT;
            default -> MutationStatus.DUPLICATE;
        };
        MutationResult result = new MutationResult(mutationId, status);
        result.setEntityId(mutation.getEntityId());
        if (stored.get("version") instanceof Number version) {
            result.setVersion(version.longValue());
        }
        if (stored.get("entityKey") instanceof String key) {
            result.setEntityKey(key);
        }
        if (stored.get("code") instanceof String code) {
            result.setCode(code);
        }
        if (status == MutationStatus.CONFLICT && stored.get("conflictFields") instanceof List<?> names) {
            List<String> fields = names.stream().map(Object::toString).toList();
            result.setConflictFields(fields);
            result.setServerFields(currentValues(mutation, principal, fields));
            result.setBaseFields(Map.of());
        }
        return Optional.of(result);
    }

    /** A mutation id that was used before, by someone else or for another item. */
    static final String MUTATION_ID_REUSED = "sync.mutation_id_reused";

    /**
     * Whether the stored answer went to this member. Answers stored before the member
     * was kept with them name the device only; a device belongs to one member for good.
     */
    private boolean sameSender(Map<String, Object> stored, UUID storedDevice, CurrentUser.Principal principal) {
        if (stored.get("memberId") instanceof String member) {
            return member.equals(principal.memberId().toString());
        }
        if (storedDevice == null) {
            return false;
        }
        return principal.memberId()
                .equals(db.select(DEVICE.MEMBER_ID)
                        .from(DEVICE)
                        .where(DEVICE.ID.eq(storedDevice))
                        .fetchOne(DEVICE.MEMBER_ID));
    }

    /** Whether the resent mutation is about the item the stored answer was about. */
    private static boolean sameItem(Map<String, Object> stored, Mutation mutation) {
        if (!(stored.get("entityId") instanceof String entityId)
                || !entityId.equals(String.valueOf(mutation.getEntityId()))) {
            return false;
        }
        // Answers stored before the type was kept with them are matched by the id.
        return !(stored.get("entityType") instanceof String entityType)
                || entityType.equals(mutation.getEntityType());
    }

    /**
     * What the conflicting fields hold now -- as far as the member may still see the item,
     * and without what only its owner may read: the share may be gone since the conflict,
     * and a board's or feed's address never leaves its owner.
     */
    private Map<String, Object> currentValues(
            Mutation mutation, CurrentUser.Principal principal, List<String> fields) {
        Map<String, Object> values = new LinkedHashMap<>();
        SyncType type = registry.find(mutation.getEntityType()).orElse(null);
        if (type == null || !visibility.maySee(principal.memberId(), type.entityType(), mutation.getEntityId())) {
            return values;
        }
        entities.load(type, mutation.getEntityId()).ifPresent(now -> {
            boolean owner = principal.memberId().equals(now.ownerId());
            for (String name : fields) {
                if (owner || !type.secretFields().contains(name)) {
                    values.put(name, now.fields().get(name));
                }
            }
        });
        return values;
    }

    private void remember(Mutation mutation, CurrentUser.Principal principal, MutationResult result) {
        UUID mutationId = mutation.getMutationId();
        UUID deviceId = principal.deviceId();
        Map<String, Object> stored = new LinkedHashMap<>();
        // Who sent it and what it was about: a resend is answered only to them, about that.
        stored.put("memberId", principal.memberId().toString());
        stored.put("entityType", mutation.getEntityType());
        stored.put("entityId", String.valueOf(mutation.getEntityId()));
        stored.put("version", result.getVersion());
        stored.put("entityKey", result.getEntityKey());
        stored.put("code", result.getCode());
        if (result.getConflictFields() != null) {
            stored.put("conflictFields", result.getConflictFields());
        }
        db.insertInto(PROCESSED_MUTATION)
                .set(PROCESSED_MUTATION.MUTATION_ID, mutationId)
                .set(PROCESSED_MUTATION.DEVICE_ID, deviceId)
                .set(PROCESSED_MUTATION.RESULT, result.getStatus().getValue())
                .set(PROCESSED_MUTATION.RESPONSE, json.write(stored))
                .onConflictDoNothing()
                .execute();
    }
}
