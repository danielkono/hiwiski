package de.danielkononov.hiwiski.media.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.EVENT;
import static de.danielkononov.hiwiski.db.generated.Tables.MEMBER;
import static de.danielkononov.hiwiski.db.generated.Tables.TODO;
import static de.danielkononov.hiwiski.db.generated.Tables.TODO_LIST;
import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_PAGE;
import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_REVISION;

import java.util.LinkedHashSet;
import java.util.Set;
import java.util.UUID;
import org.jooq.DSLContext;
import org.jooq.impl.SQLDataType;
import org.springframework.stereotype.Component;

/**
 * The items that name an image -- the same places the cleanup looks
 * ({@link OrphanedImagesJob}): a page's properties and its text, current or in a
 * revision, a list's or a task's description, an event's note, a member's picture.
 */
@Component
class MediaReferences {

    /** An item that names an image. */
    record Carrier(String type, UUID id) {}

    private final DSLContext db;

    MediaReferences(DSLContext db) {
        this.db = db;
    }

    /** Every item that names {@code imageId}, whether or not the image exists. */
    Set<Carrier> carriersNaming(UUID imageId) {
        String inText = "%" + OrphanedImagesJob.TEXT_IMAGE_SCHEME + ":" + imageId + "%";
        String anywhere = "%" + imageId + "%";
        var carriers = new LinkedHashSet<Carrier>();
        db.select(WIKI_PAGE.ID)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.CONTENT.like(inText)
                        .or(WIKI_PAGE.PROPERTIES.cast(SQLDataType.VARCHAR).like(anywhere)))
                .union(db.selectDistinct(WIKI_REVISION.PAGE_ID)
                        .from(WIKI_REVISION)
                        .where(WIKI_REVISION.CONTENT.like(inText)))
                .fetch(0, UUID.class)
                .forEach(id -> carriers.add(new Carrier("WIKI_PAGE", id)));
        db.select(TODO_LIST.ID).from(TODO_LIST).where(TODO_LIST.DESCRIPTION.like(inText))
                .fetch(TODO_LIST.ID)
                .forEach(id -> carriers.add(new Carrier("TODO_LIST", id)));
        db.select(TODO.ID).from(TODO).where(TODO.DESCRIPTION.like(inText))
                .fetch(TODO.ID)
                .forEach(id -> carriers.add(new Carrier("TODO", id)));
        db.select(EVENT.ID).from(EVENT).where(EVENT.DESCRIPTION.like(inText))
                .fetch(EVENT.ID)
                .forEach(id -> carriers.add(new Carrier("EVENT", id)));
        db.select(MEMBER.ID).from(MEMBER).where(MEMBER.AVATAR_IMAGE_ID.eq(imageId))
                .fetch(MEMBER.ID)
                .forEach(id -> carriers.add(new Carrier(MediaCarriers.MEMBER, id)));
        return carriers;
    }
}
