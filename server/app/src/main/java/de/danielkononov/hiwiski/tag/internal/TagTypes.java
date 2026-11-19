package de.danielkononov.hiwiski.tag.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.TAG;

import de.danielkononov.hiwiski.access.JooqOwnable;
import de.danielkononov.hiwiski.access.Ownable;
import de.danielkononov.hiwiski.admin.JooqRestorable;
import de.danielkononov.hiwiski.admin.Restorable;
import de.danielkononov.hiwiski.sync.SyncField;
import de.danielkononov.hiwiski.sync.SyncType;
import java.util.List;
import org.jooq.DSLContext;
import org.jooq.Table;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Tags: an item of their own with an owner and a share.
 *
 * <p>The whole wiring is here: sync, share, trash. The assignment to items is a field
 * {@code tags} on the items themselves and is registered there: so it travels with the
 * item through sync, with its share and its conflict check, like {@code assignees}. A
 * table of its own would need an entity of its own, with a share of its own, for
 * something that has no owner of its own.
 */
@Configuration
class TagTypes {

    static final String TAG_TYPE = "TAG";

    @Bean
    SyncType tagSyncType() {
        return new SyncType() {
            @Override
            public String entityType() {
                return TAG_TYPE;
            }

            @Override
            public Table<?> table() {
                return TAG;
            }

            @Override
            public List<SyncField<?>> fields() {
                return List.of(
                        SyncField.text("name", TAG.NAME),
                        SyncField.text("colorToken", TAG.COLOR_TOKEN));
            }
        };
    }

    /** A tag is not a container and inherits from no one — it is shared directly. */
    @Bean
    Ownable tagOwnable(DSLContext db) {
        return new JooqOwnable(db, TAG_TYPE, TAG);
    }

    @Bean
    Restorable tagRestorable(DSLContext db) {
        return new JooqRestorable(db, TAG_TYPE, TAG, TAG.NAME, null, null, null);
    }
}
