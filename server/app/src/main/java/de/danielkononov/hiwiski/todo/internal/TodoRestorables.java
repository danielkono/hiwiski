package de.danielkononov.hiwiski.todo.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.TODO;
import static de.danielkononov.hiwiski.db.generated.Tables.TODO_LIST;

import de.danielkononov.hiwiski.admin.JooqRestorable;
import de.danielkononov.hiwiski.admin.Restorable;
import org.jooq.DSLContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * What {@code todo} contributes to the trash.
 *
 * <p>Occurrences of a series are not in it: they are not an item someone deletes by
 * accident, but a check mark. Whoever restores the task gets them along with it.
 */
@Configuration
class TodoRestorables {

    @Bean
    Restorable todoListRestorable(DSLContext db) {
        return new JooqRestorable(db, TodoSyncTypes.TODO_LIST_TYPE, TODO_LIST, TODO_LIST.NAME, TODO_LIST.ENTITY_KEY, null, null);
    }

    @Bean
    Restorable todoRestorable(DSLContext db) {
        return new JooqRestorable(
                db, TodoSyncTypes.TODO_TYPE, TODO, TODO.TITLE, TODO.ENTITY_KEY, TODO.LIST_ID, TODO_LIST);
    }
}
