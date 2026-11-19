package de.danielkononov.hiwiski.sync.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.CHANGE_LOG;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.jooq.Condition;
import org.jooq.DSLContext;
import org.jooq.Record;
import org.jooq.impl.DSL;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * The change log: the basis for sync <em>and</em> history.
 *
 * <p>It is written <strong>synchronously in the same transaction</strong> as the
 * mutation, never via an event. An event after the commit would be lost in
 * a crash, and no client would learn of the change. Events are exclusively for side
 * effects afterwards: search index, SSE signal, cleanup jobs.
 */
@Repository
class ChangeLogRepository implements de.danielkononov.hiwiski.sync.ChangeHistory {

    private final DSLContext db;
    private final SyncJson json;

    ChangeLogRepository(DSLContext db, SyncJson json) {
        this.db = db;
        this.json = json;
    }

    record Entry(
            long seq,
            String entityType,
            UUID entityId,
            String containerType,
            UUID containerId,
            String op,
            Map<String, Object> fields,
            long entityVersion,
            String entityKey) {}

    @Transactional(propagation = Propagation.MANDATORY)
    void append(
            long seq,
            String entityType,
            UUID entityId,
            String containerType,
            UUID containerId,
            String op,
            Map<String, Object> fields,
            List<String> changedFields,
            UUID actorMemberId,
            UUID actorDeviceId,
            long entityVersion) {
        append(seq, entityType, entityId, containerType, containerId, op, fields, changedFields,
                actorMemberId, actorDeviceId, entityVersion, null);
    }

    /** As above, with the readable key — it travels along in the envelope. */
    @Transactional(propagation = Propagation.MANDATORY)
    void append(
            long seq,
            String entityType,
            UUID entityId,
            String containerType,
            UUID containerId,
            String op,
            Map<String, Object> fields,
            List<String> changedFields,
            UUID actorMemberId,
            UUID actorDeviceId,
            long entityVersion,
            String entityKey) {
        db.insertInto(CHANGE_LOG)
                .set(CHANGE_LOG.SEQ, seq)
                .set(CHANGE_LOG.ENTITY_TYPE, entityType)
                .set(CHANGE_LOG.ENTITY_ID, entityId)
                .set(CHANGE_LOG.CONTAINER_TYPE, containerType)
                .set(CHANGE_LOG.CONTAINER_ID, containerId)
                .set(CHANGE_LOG.OP, op)
                .set(CHANGE_LOG.FIELDS, json.write(fields))
                .set(CHANGE_LOG.CHANGED_FIELDS, changedFields.toArray(String[]::new))
                .set(CHANGE_LOG.ACTOR_MEMBER_ID, actorMemberId)
                .set(CHANGE_LOG.ACTOR_DEVICE_ID, actorDeviceId)
                .set(CHANGE_LOG.ENTITY_VERSION, entityVersion)
                .set(CHANGE_LOG.ENTITY_KEY, entityKey)
                .execute();
    }

    /**
     * The delta, filtered and ascending.
     *
     * <p>The visibility condition goes into the <em>same</em> query. A second step would
     * be a time window.
     */
    @Transactional(readOnly = true)
    List<Entry> since(long lastSeq, Condition visibility, int limit) {
        return db.select(
                        CHANGE_LOG.SEQ,
                        CHANGE_LOG.ENTITY_TYPE,
                        CHANGE_LOG.ENTITY_ID,
                        CHANGE_LOG.CONTAINER_TYPE,
                        CHANGE_LOG.CONTAINER_ID,
                        CHANGE_LOG.OP,
                        CHANGE_LOG.FIELDS,
                        CHANGE_LOG.ENTITY_VERSION,
                        CHANGE_LOG.ENTITY_KEY)
                .from(CHANGE_LOG)
                .where(CHANGE_LOG.SEQ.gt(lastSeq))
                .and(visibility)
                .orderBy(CHANGE_LOG.SEQ.asc())
                .limit(limit)
                .fetch(this::toEntry);
    }

    /** The device that wrote the change at this position — empty for the server itself. */
    @Transactional(readOnly = true)
    java.util.Optional<UUID> deviceOf(long seq) {
        return java.util.Optional.ofNullable(db.select(CHANGE_LOG.ACTOR_DEVICE_ID)
                .from(CHANGE_LOG)
                .where(CHANGE_LOG.SEQ.eq(seq))
                .fetchOne(CHANGE_LOG.ACTOR_DEVICE_ID));
    }

    /**
     * The value a field had at a position: the last change to it up to there.
     *
     * <p>For the conflict view — what both sides started from. Empty when the field was
     * never written up to then or the log no longer reaches back that far (retention).
     */
    @Transactional(readOnly = true)
    @Override
    public java.util.Optional<java.util.Map.Entry<String, Object>> valueAt(
            String entityType, UUID entityId, String field, long seq) {
        var row = db.select(CHANGE_LOG.FIELDS)
                .from(CHANGE_LOG)
                .where(CHANGE_LOG.ENTITY_TYPE.eq(entityType))
                .and(CHANGE_LOG.ENTITY_ID.eq(entityId))
                .and(CHANGE_LOG.SEQ.le(seq))
                .and(CHANGE_LOG.OP.eq("upsert"))
                .and(DSL.condition("jsonb_exists({0}, {1})", CHANGE_LOG.FIELDS, DSL.val(field)))
                .orderBy(CHANGE_LOG.SEQ.desc())
                .limit(1)
                .fetchOne();
        if (row == null) {
            return java.util.Optional.empty();
        }
        // An entry, not the bare value: a field that was set to null is a value too.
        return java.util.Optional.of(new java.util.AbstractMap.SimpleEntry<>(field, json.read(row.value1()).get(field)));
    }

    private Entry toEntry(Record record) {
        return new Entry(
                record.get(CHANGE_LOG.SEQ),
                record.get(CHANGE_LOG.ENTITY_TYPE),
                record.get(CHANGE_LOG.ENTITY_ID),
                record.get(CHANGE_LOG.CONTAINER_TYPE),
                record.get(CHANGE_LOG.CONTAINER_ID),
                record.get(CHANGE_LOG.OP),
                json.read(record.get(CHANGE_LOG.FIELDS)),
                record.get(CHANGE_LOG.ENTITY_VERSION),
                record.get(CHANGE_LOG.ENTITY_KEY));
    }

    /**
     * The oldest entry still present.
     *
     * <p>If {@code lastSeq} lies before it, the client has been silent for too long and
     * needs a full resync.
     */
    @Transactional(readOnly = true)
    Optional<Long> oldestSeq() {
        return Optional.ofNullable(db.select(DSL.min(CHANGE_LOG.SEQ)).from(CHANGE_LOG).fetchOne().value1());
    }

    /** Cleanup: remove entries older than the retention period. */
    @Transactional
    int deleteOlderThan(OffsetDateTime cutoff) {
        return db.deleteFrom(CHANGE_LOG).where(CHANGE_LOG.RECORDED_AT.lt(cutoff)).execute();
    }
}
