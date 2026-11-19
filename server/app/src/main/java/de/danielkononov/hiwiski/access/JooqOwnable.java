package de.danielkononov.hiwiski.access;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.jooq.DSLContext;
import org.jooq.Field;
import org.jooq.Table;
import org.jooq.impl.DSL;

/**
 * An {@link Ownable} over the standard columns.
 *
 * <p>Every synced table carries {@code owner_id} and {@code deleted_at}, and the
 * container is a foreign key column in it. Sharing needs nothing
 * more — which is why the code lives here once and not in every domain module.
 *
 * <p>A domain module that contributes more — assignments, say — overrides the
 * corresponding method.
 */
public class JooqOwnable implements Ownable {

    private final DSLContext db;
    private final String itemType;
    private final Table<?> table;
    private final String containerType;
    private final Field<UUID> containerColumn;

    public JooqOwnable(DSLContext db, String itemType, Table<?> table) {
        this(db, itemType, table, null, null);
    }

    public JooqOwnable(
            DSLContext db,
            String itemType,
            Table<?> table,
            String containerType,
            Field<UUID> containerColumn) {
        this.db = db;
        this.itemType = itemType;
        this.table = table;
        this.containerType = containerType;
        this.containerColumn = containerColumn;
    }

    protected DSLContext db() {
        return db;
    }

    protected Table<?> table() {
        return table;
    }

    private Field<UUID> id() {
        return DSL.field(DSL.name(table.getName(), "id"), UUID.class);
    }

    private Field<UUID> owner() {
        return DSL.field(DSL.name(table.getName(), "owner_id"), UUID.class);
    }

    private org.jooq.Condition alive() {
        return DSL.field(DSL.name(table.getName(), "deleted_at")).isNull();
    }

    @Override
    public String itemType() {
        return itemType;
    }

    @Override
    public Optional<UUID> ownerOf(UUID itemId) {
        return Optional.ofNullable(
                db.select(owner()).from(table).where(id().eq(itemId)).fetchOne(owner()));
    }

    @Override
    public Optional<String> containerType() {
        return Optional.ofNullable(containerType);
    }

    @Override
    public Optional<ItemRef> containerOf(UUID itemId) {
        if (containerColumn == null) {
            return Optional.empty();
        }
        return Optional.ofNullable(
                        db.select(containerColumn)
                                .from(table)
                                .where(id().eq(itemId))
                                .fetchOne(containerColumn))
                .map(value -> new ItemRef(containerType, value));
    }

    @Override
    public List<UUID> inContainer(UUID containerId) {
        if (containerColumn == null) {
            return List.of();
        }
        return db.select(id())
                .from(table)
                .where(containerColumn.eq(containerId))
                .and(alive())
                .fetch(id());
    }

    /**
     * For {@link #assignmentWritten}, over an assignee column and the column of the
     * owner's choices: the owner's choices plus those the owner just added, of which only
     * those still assigned stay.
     */
    protected void keepOwnerAssignees(
            UUID itemId,
            Field<UUID[]> assignees,
            Field<UUID[]> ownerAssignees,
            java.util.Collection<UUID> chosenByOwner) {
        Field<UUID[]> kept = DSL.field(
                "array(select distinct a from unnest({0} || {2}) as a where a = any({1}))",
                ownerAssignees.getDataType(),
                ownerAssignees,
                assignees,
                DSL.val(chosenByOwner.toArray(UUID[]::new), ownerAssignees.getDataType()));
        db.update(table).set(ownerAssignees, kept).where(id().eq(itemId)).execute();
    }

    /** Reads a UUID array column of one item -- empty if there is none. */
    protected List<UUID> uuids(UUID itemId, Field<UUID[]> column) {
        UUID[] values = db.select(column).from(table).where(id().eq(itemId)).fetchOne(column);
        return values == null ? List.of() : java.util.Arrays.asList(values);
    }

    @Override
    public List<UUID> allInContainer(UUID containerId) {
        if (containerColumn == null) {
            return List.of();
        }
        return db.select(id()).from(table).where(containerColumn.eq(containerId)).fetch(id());
    }

    @Override
    public List<UUID> ownedBy(UUID memberId) {
        return db.select(id()).from(table).where(owner().eq(memberId)).and(alive()).fetch(id());
    }
}
