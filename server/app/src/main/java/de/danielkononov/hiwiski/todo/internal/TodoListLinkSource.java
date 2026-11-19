package de.danielkononov.hiwiski.todo.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.TODO_LIST;

import de.danielkononov.hiwiski.link.LinkSource;
import java.util.Optional;
import java.util.UUID;
import org.jooq.DSLContext;
import org.springframework.stereotype.Component;

/**
 * Lists as link targets — "the shopping list" in a comment — and their description as a
 * source. Cited by its address or by its number, {@code #LST-3}.
 */
@Component
class TodoListLinkSource implements LinkSource {

    private final DSLContext db;

    TodoListLinkSource(DSLContext db) {
        this.db = db;
    }

    @Override
    public String itemType() {
        return "TODO_LIST";
    }

    @Override
    public String textOf(UUID itemId) {
        return db.select(TODO_LIST.DESCRIPTION)
                .from(TODO_LIST)
                .where(TODO_LIST.ID.eq(itemId))
                .fetchOne(TODO_LIST.DESCRIPTION);
    }

    @Override
    public Optional<String> titleOf(UUID itemId) {
        return Optional.ofNullable(db.select(TODO_LIST.NAME)
                .from(TODO_LIST)
                .where(TODO_LIST.ID.eq(itemId))
                .and(TODO_LIST.DELETED_AT.isNull())
                .fetchOne(TODO_LIST.NAME));
    }

    @Override
    public Optional<String> entityKeyOf(UUID itemId) {
        return Optional.ofNullable(db.select(TODO_LIST.ENTITY_KEY)
                .from(TODO_LIST)
                .where(TODO_LIST.ID.eq(itemId))
                .fetchOne(TODO_LIST.ENTITY_KEY));
    }

    @Override
    public Optional<UUID> byEntityKey(String entityKey) {
        return Optional.ofNullable(db.select(TODO_LIST.ID)
                .from(TODO_LIST)
                .where(TODO_LIST.ENTITY_KEY.eq(entityKey))
                .and(TODO_LIST.DELETED_AT.isNull())
                .fetchOne(TODO_LIST.ID));
    }
}
