package de.danielkononov.hiwiski.todo.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.LIST_ORDER;

import de.danielkononov.hiwiski.access.JooqOwnable;
import de.danielkononov.hiwiski.access.Ownable;
import de.danielkononov.hiwiski.sync.SyncField;
import de.danielkononov.hiwiski.sync.SyncType;
import java.util.List;
import org.jooq.DSLContext;
import org.jooq.Table;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Each member's own order of the task lists on the overview.
 *
 * <p>A list's {@code position} is the family's; this order is a personal preference.
 * One item per member, owned by them and shared with no one, so it travels to all of
 * their devices -- offline too -- and to nobody else. Its id is the member's id: every
 * device writes the same item.
 */
@Configuration
class ListOrderTypes {

    static final String LIST_ORDER_TYPE = "LIST_ORDER";

    @Bean
    SyncType listOrderSyncType() {
        return new SyncType() {
            @Override
            public String entityType() {
                return LIST_ORDER_TYPE;
            }

            @Override
            public Table<?> table() {
                return LIST_ORDER;
            }

            @Override
            public List<SyncField<?>> fields() {
                // Replaced as a whole: two devices sorting at once conflict instead of
                // producing an order nobody chose.
                return List.of(SyncField.json("listIds", LIST_ORDER.LIST_IDS));
            }
        };
    }

    /** Not a container, inherits from no one, and nobody shares it: the owner alone. */
    @Bean
    Ownable listOrderOwnable(DSLContext db) {
        return new JooqOwnable(db, LIST_ORDER_TYPE, LIST_ORDER) {

            @Override
            public boolean shareable() {
                return false;
            }

            @Override
            public boolean idIsOwner() {
                return true;
            }
        };
    }
}
