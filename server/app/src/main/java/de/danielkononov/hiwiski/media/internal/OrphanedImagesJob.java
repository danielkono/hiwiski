package de.danielkononov.hiwiski.media.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.EVENT;
import static de.danielkononov.hiwiski.db.generated.Tables.MEDIA;
import static de.danielkononov.hiwiski.db.generated.Tables.MEMBER;
import static de.danielkononov.hiwiski.db.generated.Tables.PINBOARD_NODE;
import static de.danielkononov.hiwiski.db.generated.Tables.TODO;
import static de.danielkononov.hiwiski.db.generated.Tables.TODO_LIST;
import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_PAGE;
import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_REVISION;

import java.io.UncheckedIOException;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import org.jooq.DSLContext;
import org.jooq.Field;
import org.jooq.impl.DSL;
import org.jooq.impl.SQLDataType;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * "Orphaned images — weekly — images whose carrier is gone".
 *
 * <p>An image is orphaned if its page (or member) has been permanently deleted, or if it
 * no longer hangs on it: uploaded and then replaced, or uploaded and never set. The latter
 * only after a day — in between there may just be a sync that still delivers the
 * {@code imageId}. An image in the trash stays as long as its page is there: restoring
 * means restoring with the image.
 *
 * <p>A page hangs on an image as its recipe picture (a property, {@code imageId}) <strong>or in its
 * text</strong> ({@code ![](hiwiski-image:<id>)}) — the current one or any of its
 * revisions, or on one of the elements of its pinboard. A list and a task hang on the
 * images in their description, an event on those in its note. Counting the picture field alone took every image in a page's text away on
 * Sunday night; counting the current text alone would leave a restored revision with
 * images that are gone. Revisions go with their page, so a page deleted for good frees
 * its images.
 */
@Component
class OrphanedImagesJob {

    private static final Logger log = LoggerFactory.getLogger(OrphanedImagesJob.class);

    private static final Duration GRACE = Duration.ofDays(1);

    /** The scheme of an image in a page's text — the app writes {@code ![](hiwiski-image:<id>)}. */
    static final String TEXT_IMAGE_SCHEME = "hiwiski-image";

    private final DSLContext db;
    private final MediaStore store;
    private final TransactionTemplate transaction;

    OrphanedImagesJob(DSLContext db, MediaStore store, PlatformTransactionManager transactions) {
        this.db = db;
        this.store = store;
        this.transaction = new TransactionTemplate(transactions);
    }

    /**
     * The rows first, committed; then the files, one at a time.
     *
     * <p>In one transaction, a file that could not be deleted rolled back every row
     * delete -- while the files deleted before it stayed gone, so rows came back that
     * pointed at nothing, every week again.
     */
    @Scheduled(cron = "0 50 3 * * SUN")
    public void run() {
        Integer removedRows = transaction.execute(status -> deleteOrphanedRows());
        int rows = removedRows == null ? 0 : removedRows;

        // Then the files no row points to any more.
        var live = db.selectDistinct(MEDIA.SHA256)
                .from(MEDIA)
                .where(MEDIA.SHA256.isNotNull())
                .fetchSet(MEDIA.SHA256);
        int files = 0;
        // Only files older than the grace period: an upload under way has written its
        // file, but its row is not committed yet.
        for (var sha256 : store.hashesOnDisk(Instant.now().minus(GRACE))) {
            if (live.contains(sha256)) {
                continue;
            }
            try {
                store.delete(sha256);
                files++;
            } catch (UncheckedIOException e) {
                // One file that will not go does not keep the others.
                log.warn("media: could not delete {}", sha256, e);
            }
        }
        files += store.deleteLeftovers(Instant.now().minus(GRACE), live);
        if (rows > 0 || files > 0) {
            log.info("media: removed {} orphaned images and {} files", rows, files);
        }
    }

    private int deleteOrphanedRows() {
        // A member's picture counts like a page's image -- without this line the job
        // took every avatar away on Sunday night.
        // "%hiwiski-image:<id>%": the image named in a page's text.
        // "%<id>%": the image's id anywhere in a page's properties.
        Field<String> anywhere =
                DSL.concat(DSL.inline("%"), MEDIA.ID.cast(SQLDataType.VARCHAR), DSL.inline("%"));
        Field<String> inText = DSL.concat(
                DSL.inline("%" + TEXT_IMAGE_SCHEME + ":"), MEDIA.ID.cast(SQLDataType.VARCHAR), DSL.inline("%"));
        var referenced = DSL.exists(DSL.selectOne()
                        .from(WIKI_PAGE)
                        .where(WIKI_PAGE.ID.eq(MEDIA.ITEM_ID))
                        // A picture a kind of page holds in its properties — a
                        // recipe's — or one named in the text.
                        .and(WIKI_PAGE.PROPERTIES.cast(SQLDataType.VARCHAR).like(anywhere)
                                .or(WIKI_PAGE.CONTENT.like(inText))))
                .or(DSL.exists(DSL.selectOne()
                        .from(WIKI_REVISION)
                        .where(WIKI_REVISION.PAGE_ID.eq(MEDIA.ITEM_ID))
                        .and(WIKI_REVISION.CONTENT.like(inText))))
                // An element of a page's pinboard: a picture element's pictures and the
                // images in a note are in its text. Deleted ones too, while they are
                // kept: they come back with their page, and their images have to be
                // there then.
                .or(DSL.exists(DSL.selectOne()
                        .from(PINBOARD_NODE)
                        .where(PINBOARD_NODE.PAGE_ID.eq(MEDIA.ITEM_ID))
                        .and(PINBOARD_NODE.TEXT.like(inText))))
                .or(DSL.exists(DSL.selectOne()
                        .from(MEMBER)
                        .where(MEMBER.ID.eq(MEDIA.ITEM_ID))
                        .and(MEMBER.AVATAR_IMAGE_ID.eq(MEDIA.ID))))
                .or(DSL.exists(DSL.selectOne()
                        .from(TODO_LIST)
                        .where(TODO_LIST.ID.eq(MEDIA.ITEM_ID))
                        .and(TODO_LIST.DESCRIPTION.like(inText))))
                .or(DSL.exists(DSL.selectOne()
                        .from(TODO)
                        .where(TODO.ID.eq(MEDIA.ITEM_ID))
                        .and(TODO.DESCRIPTION.like(inText))))
                .or(DSL.exists(DSL.selectOne()
                        .from(EVENT)
                        .where(EVENT.ID.eq(MEDIA.ITEM_ID))
                        .and(EVENT.DESCRIPTION.like(inText))));
        var carrierExists = DSL.exists(DSL.selectOne().from(WIKI_PAGE).where(WIKI_PAGE.ID.eq(MEDIA.ITEM_ID)))
                .or(DSL.exists(DSL.selectOne().from(MEMBER).where(MEMBER.ID.eq(MEDIA.ITEM_ID))))
                .or(DSL.exists(DSL.selectOne().from(TODO_LIST).where(TODO_LIST.ID.eq(MEDIA.ITEM_ID))))
                .or(DSL.exists(DSL.selectOne().from(TODO).where(TODO.ID.eq(MEDIA.ITEM_ID))))
                .or(DSL.exists(DSL.selectOne().from(EVENT).where(EVENT.ID.eq(MEDIA.ITEM_ID))));

        return db.deleteFrom(MEDIA)
                .where(DSL.not(carrierExists))
                .or(DSL.not(referenced).and(MEDIA.CREATED_AT.lt(OffsetDateTime.now().minus(GRACE))))
                .execute();
    }
}
