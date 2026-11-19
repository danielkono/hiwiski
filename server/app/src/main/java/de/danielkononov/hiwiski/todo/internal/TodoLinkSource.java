package de.danielkononov.hiwiski.todo.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.TODO;

import de.danielkononov.hiwiski.link.LinkSource;
import java.util.Optional;
import java.util.UUID;
import org.jooq.DSLContext;
import org.springframework.stereotype.Component;

/**
 * What {@code todo} registers with {@code link}.
 *
 * <p>A task is usually the <em>target</em> of a reference, not the source — but its
 * description can carry one too.
 */
@Component
class TodoLinkSource implements LinkSource {

    private final DSLContext db;

    TodoLinkSource(DSLContext db) {
        this.db = db;
    }

    @Override
    public String itemType() {
        return "TODO";
    }

    @Override
    public String textOf(UUID itemId) {
        return db.select(TODO.DESCRIPTION).from(TODO).where(TODO.ID.eq(itemId)).fetchOne(TODO.DESCRIPTION);
    }

    @Override
    public Optional<String> titleOf(UUID itemId) {
        return Optional.ofNullable(db.select(TODO.TITLE)
                .from(TODO)
                .where(TODO.ID.eq(itemId))
                .and(TODO.DELETED_AT.isNull())
                .fetchOne(TODO.TITLE));
    }

    @Override
    public Optional<String> entityKeyOf(UUID itemId) {
        return Optional.ofNullable(
                db.select(TODO.ENTITY_KEY).from(TODO).where(TODO.ID.eq(itemId)).fetchOne(TODO.ENTITY_KEY));
    }

    @Override
    public Optional<UUID> byEntityKey(String entityKey) {
        return Optional.ofNullable(db.select(TODO.ID)
                .from(TODO)
                .where(TODO.ENTITY_KEY.eq(entityKey))
                .and(TODO.DELETED_AT.isNull())
                .fetchOne(TODO.ID));
    }
}
