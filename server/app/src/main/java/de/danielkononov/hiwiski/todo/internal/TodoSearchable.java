package de.danielkononov.hiwiski.todo.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.TODO;
import static de.danielkononov.hiwiski.db.generated.Tables.TODO_LIST;

import de.danielkononov.hiwiski.search.Searchable;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.function.BiPredicate;
import org.jooq.DSLContext;
import org.springframework.stereotype.Component;

/** What {@code todo} registers with {@code search}. */
@Component
class TodoSearchable implements Searchable {

    private final DSLContext db;

    TodoSearchable(DSLContext db) {
        this.db = db;
    }

    @Override
    public String itemType() {
        return "TODO";
    }

    @Override
    public Optional<Entry> entryOf(UUID itemId) {
        var row = db.select(
                        TODO.OWNER_ID,
                        TODO.TITLE,
                        TODO.DESCRIPTION,
                        TODO.ENTITY_KEY,
                        TODO_LIST.NAME,
                        TODO_LIST.ARCHIVED_AT)
                .from(TODO)
                .leftJoin(TODO_LIST)
                .on(TODO_LIST.ID.eq(TODO.LIST_ID))
                .where(TODO.ID.eq(itemId))
                .and(TODO.DELETED_AT.isNull())
                .fetchOne();

        return row == null
                ? Optional.empty()
                : Optional.of(new Entry(
                        row.value1(),
                        row.value2(),
                        row.value3() == null ? "" : row.value3(),
                        row.value4(),
                        // Where it was found: "Household · Task".
                        row.value5(),
                        // Archived with its list.
                        row.value6() != null));
    }

    /** The list's name — if the reader may see the list, not only the task. */
    @Override
    public String contextFor(UUID itemId, String indexed, BiPredicate<String, UUID> visible) {
        var row = db.select(TODO_LIST.ID, TODO_LIST.NAME)
                .from(TODO)
                .join(TODO_LIST)
                .on(TODO_LIST.ID.eq(TODO.LIST_ID))
                .where(TODO.ID.eq(itemId))
                .fetchOne();
        return row != null && visible.test(TodoSyncTypes.TODO_LIST_TYPE, row.value1()) ? row.value2() : null;
    }

    /** Archiving or restoring a list changes the entries of all its tasks. */
    @Override
    public List<UUID> affectedBy(String entityType, UUID entityId) {
        if (!TodoSyncTypes.TODO_LIST_TYPE.equals(entityType)) {
            return List.of();
        }
        return db.select(TODO.ID)
                .from(TODO)
                .where(TODO.LIST_ID.eq(entityId))
                .and(TODO.DELETED_AT.isNull())
                .fetch(TODO.ID);
    }
}
