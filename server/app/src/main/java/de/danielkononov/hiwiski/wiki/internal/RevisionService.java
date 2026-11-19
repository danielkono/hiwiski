package de.danielkononov.hiwiski.wiki.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_PAGE;
import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_REVISION;

import de.danielkononov.hiwiski.sync.ChangeHistory;
import de.danielkononov.hiwiski.sync.EntityWritten;
import de.danielkononov.hiwiski.sync.FieldsRejected;
import java.util.UUID;
import org.jooq.DSLContext;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Service;

/**
 * The history of a page.
 *
 * <p><strong>Every save creates a revision</strong> — and that happens
 * here, not in the client: saving happens on leaving and every few seconds, and whether
 * that yields a revision must not depend on which app happens to be writing.
 *
 * <p>It is written <em>after</em> the mutation's commit. A revision that was created and
 * then rolled back with the mutation would be a version that never existed.
 */
@Service
class RevisionService {

    private final DSLContext db;
    private final ChangeHistory history;

    RevisionService(DSLContext db, ChangeHistory history) {
        this.db = db;
        this.history = history;
    }

    @ApplicationModuleListener
    void onEntityWritten(EntityWritten event) {
        if (!WikiSyncTypes.PAGE_TYPE.equals(event.entityType()) || event.deleted()) {
            return;
        }
        record(event.entityId(), event.actor(), "SAVE", event.version());
    }

    /**
     * Keeps the version that lost an edit conflict.
     *
     * <p>Without it, the losing side's work would be gone — and that is
     * exactly the case where someone has been writing for half an hour. Only the text
     * counts: a discarded title alone is not a version anyone would need to restore. The
     * revision's title is the one the device sent along, otherwise the current one.
     */
    @ApplicationModuleListener
    void onFieldsRejected(FieldsRejected event) {
        if (!WikiSyncTypes.PAGE_TYPE.equals(event.entityType())
                || !event.rejected().containsKey("content")) {
            return;
        }
        var current = db.select(WIKI_PAGE.TITLE).from(WIKI_PAGE).where(WIKI_PAGE.ID.eq(event.entityId())).fetchOne();
        if (current == null) {
            return;
        }
        Object title = event.fields().get("title");
        Object content = event.rejected().get("content");
        insert(
                event.entityId(),
                event.actor(),
                "CONFLICT",
                title instanceof String sent ? sent : current.value1(),
                content == null ? "" : content.toString(),
                null);
    }

    /**
     * The page as this save left it, under its author.
     *
     * <p>The listener runs after the commit, possibly after the next save. Reading the
     * page as it is by then stored Ben's text under Anna's name when Anna saved and Ben
     * saved a moment later -- and Anna's version never appeared. So the version comes
     * from the change log at this save's position; and the comparison with the last
     * revision runs under the page's lock, or two listeners with the same text both
     * found it new.
     */
    private void record(UUID pageId, UUID actor, String kind, long version) {
        lock(pageId);
        var page = db.select(WIKI_PAGE.TITLE, WIKI_PAGE.CONTENT)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.ID.eq(pageId))
                .fetchOne();
        if (page == null) {
            return;
        }
        String title = at(pageId, "title", version, page.value1());
        String content = at(pageId, "content", version, page.value2());
        // A save that changes nothing in the text is not a new version: the editor
        // saves every few seconds, and a history with a hundred identical entries is no
        // history.
        var latest = db.select(WIKI_REVISION.TITLE, WIKI_REVISION.CONTENT)
                .from(WIKI_REVISION)
                .where(WIKI_REVISION.PAGE_ID.eq(pageId))
                // Against the last *saved* version: if someone adopts a conflict
                // revision, that is a new save, even if the text equals the conflict
                // version.
                .and(WIKI_REVISION.KIND.ne("CONFLICT"))
                .orderBy(WIKI_REVISION.SEQ.desc())
                .limit(1)
                .fetchOne();
        if (latest != null && latest.value1().equals(title) && latest.value2().equals(content)) {
            return;
        }
        insert(pageId, actor, kind, title, content, version > 0 ? version : null);
    }

    /** A field as of a version -- the current value where the log does not say. */
    private String at(UUID pageId, String field, long version, String current) {
        if (version <= 0) {
            return current;
        }
        return history.valueAt(WikiSyncTypes.PAGE_TYPE, pageId, field, version)
                .map(entry -> entry.getValue() == null ? "" : entry.getValue().toString())
                .orElse(current);
    }

    /** One revision of a page at a time. */
    private void lock(UUID pageId) {
        db.select(WIKI_PAGE.ID).from(WIKI_PAGE).where(WIKI_PAGE.ID.eq(pageId)).forUpdate().fetch();
    }

    /** {@code changeSeq}: the save in the change log that left this version, if there is one. */
    private void insert(
            UUID pageId, UUID actor, String kind, String title, String content, Long changeSeq) {
        // The follow-up listeners run in parallel — in a conflict, the save and the
        // conflict revision of the same page. Without a lock both would draw the same
        // next `seq` and one would fail on the unique index.
        lock(pageId);
        Integer last = db.select(org.jooq.impl.DSL.max(WIKI_REVISION.SEQ))
                .from(WIKI_REVISION)
                .where(WIKI_REVISION.PAGE_ID.eq(pageId))
                .fetchOne(0, Integer.class);

        db.insertInto(WIKI_REVISION)
                .set(WIKI_REVISION.ID, UUID.randomUUID())
                .set(WIKI_REVISION.PAGE_ID, pageId)
                .set(WIKI_REVISION.SEQ, last == null ? 1 : last + 1)
                .set(WIKI_REVISION.TITLE, title)
                .set(WIKI_REVISION.CONTENT, content)
                .set(WIKI_REVISION.AUTHOR_ID, actor)
                .set(WIKI_REVISION.KIND, kind)
                .set(WIKI_REVISION.CHANGE_SEQ, changeSeq)
                .execute();
    }
}
