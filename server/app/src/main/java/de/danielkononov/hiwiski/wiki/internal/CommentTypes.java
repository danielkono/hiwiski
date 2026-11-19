package de.danielkononov.hiwiski.wiki.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.COMMENT;

import de.danielkononov.hiwiski.access.ItemRef;
import de.danielkononov.hiwiski.access.JooqOwnable;
import de.danielkononov.hiwiski.access.Ownable;
import de.danielkononov.hiwiski.sync.SyncField;
import de.danielkononov.hiwiski.sync.SyncType;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.jooq.DSLContext;
import org.jooq.Table;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Comments — <strong>on all items</strong>, not just on wiki pages.
 *
 * <p>The table had been there for a while, the sync type was missing: every comment came
 * back with {@code sync.unknown_entity_type} and got stuck in the outbox. The module
 * knows no domain types; {@code item_type} is a string, and the comment inherits its
 * share from its carrier, whatever its type.
 */
@Configuration
class CommentTypes {

    static final String COMMENT_TYPE = "COMMENT";

    private static final String ITEM_TYPE = "itemType";
    private static final String ITEM_ID = "itemId";
    private static final String ACCESS_DENIED = "access.denied";

    @Bean
    SyncType commentSyncType(DSLContext db) {
        return new SyncType() {
            @Override
            public String entityType() {
                return COMMENT_TYPE;
            }

            @Override
            public Table<?> table() {
                return COMMENT;
            }

            @Override
            public List<SyncField<?>> fields() {
                return List.of(
                        SyncField.text(ITEM_TYPE, COMMENT.ITEM_TYPE),
                        SyncField.uuid(ITEM_ID, COMMENT.ITEM_ID),
                        SyncField.text("body", COMMENT.BODY));
            }

            /** The carrier's type, as the fields name it. */
            @Override
            public Optional<String> carrierType(Map<String, Object> fields) {
                return fields == null || fields.get(ITEM_TYPE) == null
                        ? Optional.empty()
                        : Optional.of(fields.get(ITEM_TYPE).toString());
            }

            /**
             * A comment stays on the item it was written on.
             *
             * <p>The access check sees the carrier only as the mutation's container. The
             * row stores {@code itemType}/{@code itemId} from the fields, so a new comment
             * whose fields name another item -- or an edit that changes them -- would
             * hang it on an item its author may not even read, for that item's readers
             * to see.
             */
            @Override
            public Optional<String> refusal(
                    UUID entityId, boolean exists, UUID containerId, Map<String, Object> fields) {
                Map<String, Object> changes = fields == null ? Map.of() : fields;
                if (!exists) {
                    Object itemId = changes.get(ITEM_ID);
                    return itemId != null && itemId.toString().equals(String.valueOf(containerId))
                            ? Optional.empty()
                            : Optional.of(ACCESS_DENIED);
                }
                if (!changes.containsKey(ITEM_TYPE) && !changes.containsKey(ITEM_ID)) {
                    return Optional.empty();
                }
                var carrier = db.select(COMMENT.ITEM_TYPE, COMMENT.ITEM_ID)
                        .from(COMMENT)
                        .where(COMMENT.ID.eq(entityId))
                        .fetchOne();
                boolean same = carrier != null
                        && (!changes.containsKey(ITEM_TYPE)
                                || String.valueOf(changes.get(ITEM_TYPE)).equals(carrier.value1()))
                        && (!changes.containsKey(ITEM_ID)
                                || String.valueOf(changes.get(ITEM_ID)).equals(String.valueOf(carrier.value2())));
                return same ? Optional.empty() : Optional.of(ACCESS_DENIED);
            }
        };
    }

    @Bean
    Ownable commentOwnable(DSLContext db) {
        return new JooqOwnable(db, COMMENT_TYPE, COMMENT) {

            @Override
            public boolean attachesToAnyType() {
                return true;
            }

            @Override
            public Optional<ItemRef> containerOf(UUID itemId) {
                return Optional.ofNullable(db()
                                .select(COMMENT.ITEM_TYPE, COMMENT.ITEM_ID)
                                .from(COMMENT)
                                .where(COMMENT.ID.eq(itemId))
                                .fetchOne())
                        .map(row -> new ItemRef(row.value1(), row.value2()));
            }

            @Override
            public List<UUID> allInContainer(UUID containerId) {
                return db().select(COMMENT.ID).from(COMMENT).where(COMMENT.ITEM_ID.eq(containerId)).fetch(COMMENT.ID);
            }

            @Override
            public List<UUID> inContainer(UUID containerId) {
                return db().select(COMMENT.ID)
                        .from(COMMENT)
                        .where(COMMENT.ITEM_ID.eq(containerId))
                        .and(COMMENT.DELETED_AT.isNull())
                        .fetch(COMMENT.ID);
            }
        };
    }
}
