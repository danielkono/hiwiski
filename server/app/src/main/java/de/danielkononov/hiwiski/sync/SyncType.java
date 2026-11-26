package de.danielkononov.hiwiski.sync;

import de.danielkononov.hiwiski.platform.KeyedEntityType;
import java.util.List;
import java.util.Optional;
import org.jooq.Field;
import org.jooq.Table;
import org.jooq.TableField;
import java.util.UUID;

/**
 * How an entity goes through sync.
 *
 * <p>This is the inversion the module structure rests on: {@code sync} knows no domain
 * types. Every domain module registers its entities here instead of {@code sync}
 * enumerating them. That is why an earlier version could add wiki, dashboard and search without
 * reaching in everywhere.
 *
 * <p>The standard columns -- {@code id}, {@code owner_id}, {@code version},
 * {@code field_seq}, {@code created_*}, {@code updated_*}, {@code deleted_*} -- exist on
 * every synced table and are <strong>not</strong> reinvented per module. {@code sync}
 * finds them by name.
 */
public interface SyncType {

    /** The name in the contract, e.g. {@code TODO}. */
    String entityType();

    Table<?> table();

    /**
     * The fields this type carries through sync.
     *
     * <p>Only the domain ones. The standard columns come by themselves.
     */
    List<SyncField<?>> fields();

    /**
     * The fields kept as keys of {@link #propertiesColumn()} rather than in columns of
     * their own — each synced, logged and conflict-checked like a column field.
     */
    default List<SyncProperty> properties() {
        return List.of();
    }

    /** The JSON column holding [properties] — needed as soon as there are any. */
    default Optional<Field<org.jooq.JSONB>> propertiesColumn() {
        return Optional.empty();
    }

    /**
     * The mutation's fields with what the server, not the client, decides: who did it,
     * and not later than now. A check-off member could otherwise name anyone as the one
     * who ticked a date off, or archived a page.
     *
     * @param actor who pushes
     * @param now the time the server received it
     * @return the fields to apply -- the same map if there is nothing to decide
     */
    default java.util.Map<String, Object> stamped(
            UUID actor, java.time.OffsetDateTime now, java.util.Map<String, Object> fields) {
        return fields;
    }

    /**
     * Sets a "who" field to the actor and keeps a "when" field from lying ahead -- for
     * {@link #stamped}. A {@code null} stays {@code null}: that is unticking or restoring.
     * A past time stays as it is: a date ticked off offline yesterday was ticked off
     * yesterday.
     */
    static java.util.Map<String, Object> stamp(
            java.util.Map<String, Object> fields,
            String who,
            String when,
            UUID actor,
            java.time.OffsetDateTime now) {
        if (fields == null || (!fields.containsKey(who) && !fields.containsKey(when))) {
            return fields;
        }
        var result = new java.util.LinkedHashMap<String, Object>(fields);
        if (result.get(who) != null) {
            result.put(who, actor.toString());
        }
        if (result.get(when) != null) {
            try {
                var at = java.time.OffsetDateTime.parse(result.get(when).toString());
                if (at.isAfter(now)) {
                    result.put(when, now.toString());
                }
            } catch (java.time.DateTimeException unreadable) {
                // Left as it is: the field's own decoding rejects it.
            }
        }
        return result;
    }

    /**
     * For a type that attaches to items of any type (a comment): the type of the carrier
     * the mutation's fields name. The access check needs it -- ids are chosen by the
     * client and unique per table only, so an id alone does not say which item is meant.
     */
    default Optional<String> carrierType(java.util.Map<String, Object> fields) {
        return Optional.empty();
    }

    /**
     * Fields only the item's owner reads and writes -- a token that opens the item without
     * signing in. Sync leaves them out of what it delivers to anyone else, and refuses a
     * write to them by anyone else.
     */
    default java.util.Set<String> secretFields() {
        return java.util.Set.of();
    }

    /**
     * The container this item inherits its share from -- e.g. the list of a task.
     * {@code null} if it is a container itself.
     */
    default Optional<Container> container() {
        return Optional.empty();
    }

    /**
     * Whether this type gets a readable key.
     *
     * <p>Four types do. It is assigned exactly once, on the first
     * sync to the server.
     */
    default Optional<KeyedEntityType> keyType() {
        return Optional.empty();
    }

    /**
     * Like {@link #keyType()}, but with the fields of the mutation.
     *
     * <p>For types whose number range depends on a field: a wiki page gets
     * {@code WIKI-3}, a recipe {@code REC-12} — and both are the same table and the same
     * entity type. It cannot be read from the database: the number is
     * assigned <em>before</em> the row exists.
     */
    default Optional<KeyedEntityType> keyType(java.util.Map<String, Object> fields) {
        return keyType();
    }

    /** The column holding the readable key. */
    default Optional<TableField<?, String>> keyColumn() {
        return Optional.empty();
    }

    /**
     * What disappears along with this item.
     *
     * <p>"For every entity, write down <strong>what disappears with it</strong> — and
     * that belongs in a test."
     * In an earlier version a deleted subscription left its external
     * calendar behind; it then sat empty in the picker for a new event and accepted
     * nothing there, being external.
     *
     * <p>The list is read <em>before</em> the delete and processed afterwards — each
     * element gets its own log entry so the devices learn of it.
     */
    default List<Ref> alsoDeleted(UUID entityId) {
        return List.of();
    }

    /**
     * What comes back along with this item when it is restored -- read after the item
     * itself is back.
     *
     * <p>For what went with it on its delete and has no place in the trash of its own: a
     * pinboard's elements went with their page, and the page came back empty without
     * them. Only what was deleted at or after {@code deletedAt} is meant -- an element
     * deleted on its own before the page stays deleted. Each element gets its own log
     * entry, like the item.
     *
     * @param deletedAt when the item itself was deleted
     */
    default List<Ref> alsoRestored(UUID entityId, java.time.OffsetDateTime deletedAt) {
        return List.of();
    }

    /**
     * Why this upsert is refused although the member may write the item — or empty.
     *
     * <p>For rules that belong to the state of the item rather than to the member: an
     * archived page or list is read-only, and so is everything in it. The
     * access check has already passed when this is asked; deletions do not come here.
     *
     * @param exists whether the item exists already (deleted or not)
     * @param containerId the container the mutation names, or the current one
     * @param fields the fields of the mutation
     * @return an error code for the rejection
     */
    default Optional<String> refusal(UUID entityId, boolean exists, UUID containerId, java.util.Map<String, Object> fields) {
        return Optional.empty();
    }

    /**
     * @param type the name of the container type in the contract
     * @param column the foreign key column
     */
    record Container(String type, Field<UUID> column) {}

    /** An item, named without its type. */
    record Ref(String entityType, UUID entityId) {}
}
