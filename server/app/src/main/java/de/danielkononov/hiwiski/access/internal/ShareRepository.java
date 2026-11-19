package de.danielkononov.hiwiski.access.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.SHARE;

import de.danielkononov.hiwiski.access.Access;
import de.danielkononov.hiwiski.access.AccessLevel;
import java.util.List;
import java.util.UUID;
import org.jooq.DSLContext;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

@Repository
class ShareRepository {

    private final DSLContext db;

    ShareRepository(DSLContext db) {
        this.db = db;
    }

    record ShareRow(Access.SubjectType subjectType, UUID subjectId, AccessLevel level) {}

    @Transactional(readOnly = true)
    List<ShareRow> of(String itemType, UUID itemId) {
        return db.select(SHARE.SUBJECT_TYPE, SHARE.SUBJECT_ID, SHARE.LEVEL)
                .from(SHARE)
                .where(SHARE.ITEM_TYPE.eq(itemType))
                .and(SHARE.ITEM_ID.eq(itemId))
                .fetch(record -> new ShareRow(
                        Access.SubjectType.valueOf(record.value1()),
                        record.value2(),
                        AccessLevel.parse(record.value3())));
    }

    @Transactional(readOnly = true)
    boolean anyFor(String itemType, UUID itemId) {
        return db.fetchExists(db.selectOne()
                .from(SHARE)
                .where(SHARE.ITEM_TYPE.eq(itemType))
                .and(SHARE.ITEM_ID.eq(itemId)));
    }

    /**
     * Replaces an item's direct shares.
     *
     * <p>Replace and not add: <strong>a direct share replaces the inherited one, it does
     * not add to it</strong>. An empty list therefore falls back to the
     * inherited one.
     */
    @Transactional
    void replace(String itemType, UUID itemId, List<ShareRow> shares, UUID actor) {
        db.deleteFrom(SHARE)
                .where(SHARE.ITEM_TYPE.eq(itemType))
                .and(SHARE.ITEM_ID.eq(itemId))
                .execute();
        for (ShareRow share : shares) {
            db.insertInto(SHARE)
                    .set(SHARE.ITEM_TYPE, itemType)
                    .set(SHARE.ITEM_ID, itemId)
                    .set(SHARE.SUBJECT_TYPE, share.subjectType().name())
                    .set(SHARE.SUBJECT_ID, share.subjectId())
                    .set(SHARE.LEVEL, share.level().name())
                    .set(SHARE.CREATED_BY, actor)
                    .onConflictDoNothing()
                    .execute();
        }
    }

    /** The items shared directly with this recipient. */
    @Transactional(readOnly = true)
    List<de.danielkononov.hiwiski.access.ItemRef> itemsFor(Access.SubjectType subjectType, UUID subjectId) {
        return db.selectDistinct(SHARE.ITEM_TYPE, SHARE.ITEM_ID)
                .from(SHARE)
                .where(SHARE.SUBJECT_TYPE.eq(subjectType.name()))
                .and(SHARE.SUBJECT_ID.eq(subjectId))
                .fetch(row -> new de.danielkononov.hiwiski.access.ItemRef(row.value1(), row.value2()));
    }

    /** All items shared directly with this recipient. */
    @Transactional(readOnly = true)
    List<String> itemTypesFor(Access.SubjectType subjectType, UUID subjectId) {
        return db.selectDistinct(SHARE.ITEM_TYPE)
                .from(SHARE)
                .where(SHARE.SUBJECT_TYPE.eq(subjectType.name()))
                .and(SHARE.SUBJECT_ID.eq(subjectId))
                .fetch(SHARE.ITEM_TYPE);
    }

    /** The items of this type that carry a share of their own. */
    @Transactional(readOnly = true)
    List<UUID> itemsOfType(String itemType) {
        return db.selectDistinct(SHARE.ITEM_ID).from(SHARE).where(SHARE.ITEM_TYPE.eq(itemType)).fetch(SHARE.ITEM_ID);
    }

    /** Removes every share with this recipient -- a group that was deleted. */
    @Transactional(propagation = org.springframework.transaction.annotation.Propagation.MANDATORY)
    void removeSubject(Access.SubjectType subjectType, UUID subjectId) {
        db.deleteFrom(SHARE)
                .where(SHARE.SUBJECT_TYPE.eq(subjectType.name()))
                .and(SHARE.SUBJECT_ID.eq(subjectId))
                .execute();
    }
}
