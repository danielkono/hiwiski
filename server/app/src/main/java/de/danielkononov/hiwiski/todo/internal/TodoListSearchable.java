package de.danielkononov.hiwiski.todo.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.TODO_LIST;

import de.danielkononov.hiwiski.search.Searchable;
import java.util.Optional;
import java.util.UUID;
import org.jooq.DSLContext;
import org.springframework.stereotype.Component;

/**
 * The lists themselves, next to their tasks — an archived list has to be findable by its
 * name, not only through a task that happens to match.
 */
@Component
class TodoListSearchable implements Searchable {

    private final DSLContext db;

    TodoListSearchable(DSLContext db) {
        this.db = db;
    }

    @Override
    public String itemType() {
        return TodoSyncTypes.TODO_LIST_TYPE;
    }

    @Override
    public Optional<Entry> entryOf(UUID itemId) {
        var row = db.select(
                        TODO_LIST.OWNER_ID,
                        TODO_LIST.NAME,
                        TODO_LIST.DESCRIPTION,
                        TODO_LIST.ARCHIVED_AT,
                        TODO_LIST.ENTITY_KEY)
                .from(TODO_LIST)
                .where(TODO_LIST.ID.eq(itemId))
                .and(TODO_LIST.DELETED_AT.isNull())
                .fetchOne();

        if (row == null) {
            return Optional.empty();
        }

        return Optional.of(new Entry(
                row.value1(),
                row.value2(),
                row.value3() == null ? "" : row.value3(),
                row.value5(),
                // A list sits in nothing.
                null,
                row.value4() != null));
    }
}
