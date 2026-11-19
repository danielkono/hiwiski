package de.danielkononov.hiwiski.sync.internal;

import de.danielkononov.hiwiski.sync.SyncField;
import de.danielkononov.hiwiski.sync.SyncProperty;
import de.danielkononov.hiwiski.sync.SyncType;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.jooq.DSLContext;
import org.jooq.Field;
import org.jooq.JSONB;
import org.jooq.Record;
import org.jooq.TableField;
import org.jooq.impl.DSL;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * Reads and writes synced entities -- generically, through their {@link SyncType}.
 *
 * <p>The standard columns exist on every synced table and have the same names everywhere.
 * That is why this code finds them by name, and no domain module
 * writes the conflict resolution a second time.
 */
@Repository
class EntityRepository {

    private final DSLContext db;
    private final SyncJson json;

    EntityRepository(DSLContext db, SyncJson json) {
        this.db = db;
        this.json = json;
    }

    /**
     * The state of an entity, as far as sync needs it.
     *
     * @param fieldSeq field name to the sequence number of that field's last change
     */
    record Snapshot(
            UUID id,
            UUID ownerId,
            long version,
            Map<String, Long> fieldSeq,
            boolean deleted,
            String entityKey,
            Map<String, Object> fields) {}

    // --- The standard columns, by name -------------------------------------------

    @SuppressWarnings("unchecked")
    private static <T> Field<T> column(SyncType type, String name, Class<T> valueType) {
        Field<?> field = type.table().field(name);
        if (field == null) {
            throw new IllegalStateException(
                    type.entityType() + ": column " + name + " is missing -- every synced table has it");
        }
        return (Field<T>) field;
    }

    private static Field<UUID> id(SyncType type) {
        return column(type, "id", UUID.class);
    }

    private static Field<UUID> ownerId(SyncType type) {
        return column(type, "owner_id", UUID.class);
    }

    private static Field<Long> version(SyncType type) {
        return column(type, "version", Long.class);
    }

    private static Field<JSONB> fieldSeq(SyncType type) {
        return column(type, "field_seq", JSONB.class);
    }

    private static Field<OffsetDateTime> deletedAt(SyncType type) {
        return column(type, "deleted_at", OffsetDateTime.class);
    }

    // --- Reading -----------------------------------------------------------------

    @Transactional(readOnly = true)
    Optional<Snapshot> load(SyncType type, UUID entityId) {
        Record record = db.select().from(type.table()).where(id(type).eq(entityId)).fetchOne();
        return record == null ? Optional.empty() : Optional.of(toSnapshot(type, record));
    }

    private Snapshot toSnapshot(SyncType type, Record record) {
        Map<String, Object> values = new LinkedHashMap<>();
        for (SyncField<?> field : type.fields()) {
            values.put(field.name(), encode(field, record));
        }
        values.putAll(properties(type, record));
        String entityKey = type.keyColumn().map(record::get).orElse(null);
        return new Snapshot(
                record.get(id(type)),
                record.get(ownerId(type)),
                record.get(version(type)),
                json.readSequences(record.get(fieldSeq(type))),
                record.get(deletedAt(type)) != null,
                entityKey,
                values);
    }

    @SuppressWarnings("unchecked")
    private static <T> Object encode(SyncField<T> field, Record record) {
        return ((SyncField<Object>) field).encode().apply(record.get(field.column().getName()));
    }

    /**
     * The type's properties as the record holds them: every one the type knows, `null`
     * where the item has none — as a column field would be.
     */
    private Map<String, Object> properties(SyncType type, Record record) {
        if (type.properties().isEmpty()) {
            return Map.of();
        }
        Map<String, Object> stored = type.propertiesColumn()
                .map(column -> json.read(record.get(column)))
                .orElse(Map.of());
        Map<String, Object> values = new LinkedHashMap<>();
        for (SyncProperty property : type.properties()) {
            values.put(property.name(), stored.get(property.name()));
        }
        return values;
    }

    /**
     * All live items of this type that belong to this member.
     *
     * <p>For the full catch-up pull after {@code access_granted} and after a resync.
     */
    @Transactional(readOnly = true)
    List<Snapshot> allOwnedBy(SyncType type, UUID memberId) {
        return db.select()
                .from(type.table())
                .where(ownerId(type).eq(memberId))
                .and(deletedAt(type).isNull())
                .fetch(record -> toSnapshot(type, record));
    }

    /**
     * A live item, as the snapshot delivers it.
     *
     * @param containerId the container it inherits its share from, or none
     * @param fields all fields, not just the most recently changed ones
     */
    record Live(
            UUID id, UUID ownerId, UUID containerId, long version, String entityKey, Map<String, Object> fields) {}

    /**
     * One page of the snapshot: live items of this type, by ID, from {@code afterId}.
     *
     * @param visible the visibility, in the same query as the results
     * @param afterId the last ID of the previous page, or none
     */
    @Transactional(readOnly = true)
    List<Live> livePage(SyncType type, org.jooq.Condition visible, UUID afterId, int limit) {
        var query = db.select()
                .from(type.table())
                .where(deletedAt(type).isNull())
                .and(visible);
        if (afterId != null) {
            query = query.and(id(type).gt(afterId));
        }
        return query.orderBy(id(type).asc()).limit(limit).fetch(record -> {
            Map<String, Object> values = new LinkedHashMap<>();
            for (SyncField<?> field : type.fields()) {
                values.put(field.name(), encode(field, record));
            }
            values.putAll(properties(type, record));
            return new Live(
                    record.get(id(type)),
                    record.get(ownerId(type)),
                    type.container().map(container -> record.get(container.column())).orElse(null),
                    record.get(version(type)),
                    type.keyColumn().map(record::get).orElse(null),
                    values);
        });
    }

    /** The owners of these items, in one query -- for a page of the log. */
    @Transactional(readOnly = true)
    Map<UUID, UUID> ownersOf(SyncType type, java.util.Collection<UUID> ids) {
        if (ids.isEmpty()) {
            return Map.of();
        }
        return db.select(id(type), ownerId(type))
                .from(type.table())
                .where(id(type).in(ids))
                .fetchMap(id(type), ownerId(type));
    }

    /** The ID column -- for the snapshot's visibility condition. */
    static Field<UUID> idColumn(SyncType type) {
        return id(type);
    }

    // --- Writing -----------------------------------------------------------------

    /**
     * Creates or updates -- field by field.
     *
     * <p>If {@code field_seq[field] <= baseVersion}, it is written. If it is greater,
     * someone else has changed this field in the meantime: the field is discarded, the
     * rest of the mutation goes through.
     *
     * @return what was written and what was discarded
     */
    /**
     * Decides field by field, <strong>without writing</strong>.
     *
     * <p>Separate from writing, because a mutation with nothing left should not write at
     * all: it would bump the entity's version although nothing changed, and thereby
     * invalidate every other device's `baseVersion` -- for nothing.
     */
    UpsertResult partition(SyncType type, Snapshot current, Map<String, Object> incoming, Long baseVersion) {
        return partition(type, current, incoming, baseVersion, seq -> false);
    }

    /**
     * @param ownChange whether the change at a position came from the device sending this
     *     mutation. Its own earlier write is what it built on — a device that saves twice
     *     before the first answer arrives, or edits twice offline, carries the old
     *     {@code baseVersion} both times, and must not collide with itself.
     */
    UpsertResult partition(
            SyncType type,
            Snapshot current,
            Map<String, Object> incoming,
            Long baseVersion,
            java.util.function.LongPredicate ownChange) {
        Map<String, Object> accepted = new LinkedHashMap<>();
        List<String> rejected = new java.util.ArrayList<>();

        for (SyncField<?> field : type.fields()) {
            if (!incoming.containsKey(field.name())) {
                continue;
            }
            long lastChanged = current == null ? 0L : current.fieldSeq().getOrDefault(field.name(), 0L);
            // New entity: there is nothing to lose. A merged collection likewise -- it
            // is merged in, not replaced, and therefore cannot collide.
            boolean mayWrite = current == null
                    || field.merging()
                    || lastChanged <= (baseVersion == null ? 0L : baseVersion)
                    || ownChange.test(lastChanged);
            if (mayWrite) {
                accepted.put(field.name(), incoming.get(field.name()));
            } else {
                rejected.add(field.name());
            }
        }
        // A property is decided like a column field: by its own sequence.
        for (SyncProperty property : type.properties()) {
            if (!incoming.containsKey(property.name())) {
                continue;
            }
            long lastChanged = current == null ? 0L : current.fieldSeq().getOrDefault(property.name(), 0L);
            boolean mayWrite = current == null
                    || lastChanged <= (baseVersion == null ? 0L : baseVersion)
                    || ownChange.test(lastChanged);
            if (mayWrite) {
                accepted.put(property.name(), incoming.get(property.name()));
            } else {
                rejected.add(property.name());
            }
        }
        return new UpsertResult(accepted, rejected);
    }

    @Transactional(propagation = Propagation.MANDATORY)
    void write(
            SyncType type,
            UUID entityId,
            Snapshot current,
            Map<String, Object> accepted,
            long seq,
            UUID actor,
            UUID containerId,
            String entityKey) {

        Map<String, Long> sequences =
                current == null ? new LinkedHashMap<>() : new LinkedHashMap<>(current.fieldSeq());
        accepted.keySet().forEach(name -> sequences.put(name, seq));

        // Merged collections are MERGED IN, not replaced: two devices that set different
        // exceptions offline both get through.
        Map<String, Object> values = new LinkedHashMap<>(accepted);
        if (current != null) {
            for (SyncField<?> field : type.fields()) {
                if (!field.merging() || !values.containsKey(field.name())) {
                    continue;
                }
                // Decoded after merging: the limit holds for the whole map, which only
                // ever grows (SyncLimits.MERGED_KEYS).
                values.put(field.name(), merged(current.fields().get(field.name()), values.get(field.name())));
            }
        }

        // Properties go into their map as one patch; the other keys stay as they are.
        Map<String, Object> patch = new LinkedHashMap<>();
        for (SyncProperty property : type.properties()) {
            if (values.containsKey(property.name())) {
                patch.put(property.name(), property.normalize().apply(values.remove(property.name())));
            }
        }

        if (current == null) {
            var insert = db.insertInto(type.table())
                    .set(id(type), entityId)
                    .set(ownerId(type), actor)
                    .set(version(type), seq)
                    .set(fieldSeq(type), json.write(sequences))
                    .set(column(type, "created_by", UUID.class), actor)
                    .set(column(type, "updated_by", UUID.class), actor);
            type.container().ifPresent(container -> insert.set(container.column(), containerId));
            type.keyColumn().ifPresent(key -> insert.set(key, entityKey));
            values.forEach((name, value) -> setValue(insert, type, name, value));
            type.propertiesColumn().ifPresent(column -> insert.set(column, json.write(patch)));
            insert.execute();
            return;
        }

        var update = db.update(type.table())
                .set(version(type), seq)
                .set(fieldSeq(type), json.write(sequences))
                .set(column(type, "updated_at", OffsetDateTime.class), OffsetDateTime.now())
                .set(column(type, "updated_by", UUID.class), actor)
                // An upsert on a deleted item revives it: the user worked on it offline,
                // and silently discarding that would be data loss.
                .set(deletedAt(type), (OffsetDateTime) null);
        values.forEach((name, value) -> setValue(update, type, name, value));
        if (!patch.isEmpty()) {
            type.propertiesColumn().ifPresent(column -> update.set(
                    column,
                    DSL.field("coalesce({0}, '{}'::jsonb) || {1}", JSONB.class, column, DSL.val(json.write(patch)))));
        }
        update.where(id(type).eq(entityId)).execute();
    }

    /**
     * @param accepted the fields that were written -- they go into the log as they are
     * @param rejected the fields someone else had changed in the meantime
     */
    record UpsertResult(Map<String, Object> accepted, List<String> rejected) {}

    /** Existing keys stay, delivered ones win. */
    @SuppressWarnings("unchecked")
    private static Object merged(Object existing, Object incoming) {
        if (!(existing instanceof Map<?, ?> before) || !(incoming instanceof Map<?, ?> after)) {
            return incoming;
        }
        Map<String, Object> result = new LinkedHashMap<>((Map<String, Object>) before);
        result.putAll((Map<String, Object>) after);
        return result;
    }

    @SuppressWarnings({"unchecked", "rawtypes"})
    private void setValue(Object step, SyncType type, String name, Object value) {
        SyncField<Object> field = (SyncField<Object>) type.fields().stream()
                .filter(candidate -> candidate.name().equals(name))
                .findFirst()
                .orElseThrow();
        Object decoded = field.decode().apply(value);
        if (step instanceof org.jooq.InsertSetStep insert) {
            insert.set((Field) field.column(), decoded);
        } else {
            ((org.jooq.UpdateSetStep) step).set((Field) field.column(), decoded);
        }
    }

    /**
     * Soft delete.
     *
     * <p>Without a tombstone, a client that was offline never learns of it and creates
     * the item again on its next push. The retention period doubles as the
     * trash.
     */
    @Transactional(propagation = Propagation.MANDATORY)
    void softDelete(SyncType type, UUID entityId, long seq, UUID actor) {
        db.update(type.table())
                .set(version(type), seq)
                .set(deletedAt(type), OffsetDateTime.now())
                .set(column(type, "deleted_by", UUID.class), actor)
                .where(id(type).eq(entityId))
                .execute();
    }

    /**
     * Undoes a soft delete.
     *
     * @param containerId the container it goes into, or {@code null} to keep the old one
     * @return whether there was a deleted item to bring back
     */
    @Transactional(propagation = Propagation.MANDATORY)
    boolean restore(SyncType type, UUID entityId, UUID containerId, long seq, UUID actor) {
        var update = db.update(type.table()).set(version(type), seq);
        if (containerId != null) {
            type.container().ifPresent(container -> update.set(container.column(), containerId));
        }
        return update
                        .set(deletedAt(type), (OffsetDateTime) null)
                        .set(column(type, "deleted_by", UUID.class), (UUID) null)
                        .set(column(type, "updated_at", OffsetDateTime.class), OffsetDateTime.now())
                        .set(column(type, "updated_by", UUID.class), actor)
                        .where(id(type).eq(entityId))
                        .and(deletedAt(type).isNotNull())
                        .execute()
                == 1;
    }

    @Transactional(readOnly = true)
    Optional<UUID> containerOf(SyncType type, UUID entityId) {
        return type.container()
                .flatMap(container -> Optional.ofNullable(
                        db.select(container.column())
                                .from(type.table())
                                .where(id(type).eq(entityId))
                                .fetchOne(container.column())));
    }

    /** The column holding the readable key -- or none. */
    static Optional<TableField<?, String>> keyColumn(SyncType type) {
        return type.keyColumn();
    }

    static org.jooq.Condition notDeleted(SyncType type) {
        return DSL.field(DSL.name(type.table().getName(), "deleted_at")).isNull();
    }
}
