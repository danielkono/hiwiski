package de.danielkononov.hiwiski.admin;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.jooq.DSLContext;
import org.jooq.Field;
import org.jooq.Table;
import org.jooq.impl.DSL;

/**
 * A {@link Restorable} over the standard columns.
 *
 * <p>Every synced table carries {@code deleted_at} and {@code deleted_by}; the retention
 * period is the trash at the same time. It needs nothing more — which is
 * why the code lives here once.
 */
public class JooqRestorable implements Restorable {

    private final DSLContext db;
    private final String itemType;
    private final Table<?> table;
    private final Field<String> titleColumn;
    private final Field<String> keyColumn;
    private final Field<UUID> containerColumn;
    private final Table<?> containerTable;

    public JooqRestorable(
            DSLContext db,
            String itemType,
            Table<?> table,
            Field<String> titleColumn,
            Field<String> keyColumn,
            Field<UUID> containerColumn,
            Table<?> containerTable) {
        this.db = db;
        this.itemType = itemType;
        this.table = table;
        this.titleColumn = titleColumn;
        this.keyColumn = keyColumn;
        this.containerColumn = containerColumn;
        this.containerTable = containerTable;
    }

    private Field<UUID> id() {
        return DSL.field(DSL.name(table.getName(), "id"), UUID.class);
    }

    private Field<UUID> owner() {
        return DSL.field(DSL.name(table.getName(), "owner_id"), UUID.class);
    }

    private Field<OffsetDateTime> deletedAt() {
        return DSL.field(DSL.name(table.getName(), "deleted_at"), OffsetDateTime.class);
    }

    private Field<UUID> deletedBy() {
        return DSL.field(DSL.name(table.getName(), "deleted_by"), UUID.class);
    }

    @Override
    public String itemType() {
        return itemType;
    }

    @Override
    public List<Deleted> deleted(Instant notBefore) {
        // Only what the trash shows, and whether the container is gone in the same query:
        // every column of every deleted item — a page's whole text — and two more queries
        // per item made a trash of a few thousand entries take seconds.
        Field<String> title = titleColumn == null ? DSL.inline("") : titleColumn;
        Field<String> key = keyColumn == null ? DSL.inline((String) null, String.class) : keyColumn;
        return db.select(id(), owner(), title, key, deletedAt(), deletedBy(), containerGone())
                .from(table)
                .where(deletedAt().isNotNull())
                .and(deletedAt().ge(notBefore.atOffset(ZoneOffset.UTC)))
                .orderBy(deletedAt().desc())
                .fetch(record -> new Deleted(
                        record.value1(),
                        record.value2(),
                        String.valueOf(record.value3()),
                        record.value4(),
                        record.value5().toInstant(),
                        record.value6(),
                        Boolean.TRUE.equals(record.value7())));
    }

    /**
     * Whether an item's container is gone, as a column of the item's row: it has one, and
     * no living container of that id exists. No container is not a missing one — a
     * top-level page has no parent and never had one.
     */
    private Field<Boolean> containerGone() {
        if (containerColumn == null || containerTable == null) {
            return DSL.inline(false);
        }
        // Aliased: a page's container is a page, the same table.
        var container = containerTable.as("container");
        Field<UUID> containerId = DSL.field(DSL.name("container", "id"), UUID.class);
        Field<OffsetDateTime> containerDeleted =
                DSL.field(DSL.name("container", "deleted_at"), OffsetDateTime.class);
        Field<UUID> ownContainer = DSL.field(DSL.name(table.getName(), containerColumn.getName()), UUID.class);
        return DSL.field(ownContainer.isNotNull().and(DSL.notExists(DSL.selectOne()
                .from(container)
                .where(containerId.eq(ownContainer))
                .and(containerDeleted.isNull()))));
    }

    @Override
    public boolean containerGone(UUID itemId) {
        if (containerColumn == null || containerTable == null) {
            return false;
        }
        UUID containerId = db.select(containerColumn).from(table).where(id().eq(itemId)).fetchOne(containerColumn);
        if (containerId == null) {
            // No container is not a missing one: a top-level page has no parent and
            // never had one.
            return false;
        }
        Field<UUID> containerId2 = DSL.field(DSL.name(containerTable.getName(), "id"), UUID.class);
        Field<OffsetDateTime> containerDeleted =
                DSL.field(DSL.name(containerTable.getName(), "deleted_at"), OffsetDateTime.class);
        return !db.fetchExists(db.selectOne()
                .from(containerTable)
                .where(containerId2.eq(containerId))
                .and(containerDeleted.isNull()));
    }

    @Override
    public Optional<UUID> deletedOwnerOf(UUID itemId) {
        return Optional.ofNullable(db.select(owner())
                .from(table)
                .where(id().eq(itemId))
                .and(deletedAt().isNotNull())
                .fetchOne(owner()));
    }

    @Override
    public int purgeOlderThan(Instant cutoff) {
        return db.deleteFrom(table)
                .where(deletedAt().isNotNull())
                .and(deletedAt().lt(cutoff.atOffset(ZoneOffset.UTC)))
                .execute();
    }

    @Override
    public Optional<String> titleOf(UUID itemId) {
        if (titleColumn == null) {
            return Optional.empty();
        }
        return Optional.ofNullable(db.select(titleColumn).from(table).where(id().eq(itemId)).fetchOne(titleColumn));
    }
}
