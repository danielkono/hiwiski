package de.danielkononov.hiwiski.wiki.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.PINBOARD_EDGE;
import static de.danielkononov.hiwiski.db.generated.Tables.PINBOARD_NODE;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.jooq.DSLContext;
import org.springframework.stereotype.Component;

/**
 * What a pinboard says, as text: the texts of its elements, the items its link elements
 * point to, and the labels of its connections.
 *
 * <p>Counted as part of its page. A reference in an element is one from the page -- the
 * item it points to says "the pinboard X links here" -- and a search finds the page by
 * a word on its canvas. An element is no item a person cites or finds on its own.
 */
@Component
class PinboardTexts {

    /** The elements that point to an item. */
    private static final String LINK_KIND = "LINK";

    private final DSLContext db;

    PinboardTexts(DSLContext db) {
        this.db = db;
    }

    /** The map's texts, one per line, in the order the elements were created. */
    String of(UUID pageId) {
        List<String> lines = new ArrayList<>();
        db.select(PINBOARD_NODE.TEXT, PINBOARD_NODE.TARGET, PINBOARD_NODE.KIND)
                .from(PINBOARD_NODE)
                .where(PINBOARD_NODE.PAGE_ID.eq(pageId))
                .and(PINBOARD_NODE.DELETED_AT.isNull())
                .orderBy(PINBOARD_NODE.ID)
                .forEach(row -> {
                    if (!row.value1().isBlank()) {
                        lines.add(row.value1());
                    }
                    // A bare address: the parser reads it outside a Markdown link too.
                    // A link element's only -- the member an element shows is no item
                    // the page links to.
                    if (row.value2() != null && LINK_KIND.equals(row.value3())) {
                        lines.add(row.value2());
                    }
                });
        db.select(PINBOARD_EDGE.TEXT)
                .from(PINBOARD_EDGE)
                .where(PINBOARD_EDGE.PAGE_ID.eq(pageId))
                .and(PINBOARD_EDGE.DELETED_AT.isNull())
                .and(PINBOARD_EDGE.TEXT.ne(""))
                .orderBy(PINBOARD_EDGE.ID)
                .forEach(row -> lines.add(row.value1()));
        return String.join("\n", lines);
    }

    /** The page an element or a connection is on -- empty for anything else. */
    Optional<UUID> pageOf(String entityType, UUID entityId) {
        if (PinboardSyncTypes.NODE_TYPE.equals(entityType)) {
            return Optional.ofNullable(db.select(PINBOARD_NODE.PAGE_ID)
                    .from(PINBOARD_NODE)
                    .where(PINBOARD_NODE.ID.eq(entityId))
                    .fetchOne(PINBOARD_NODE.PAGE_ID));
        }
        if (PinboardSyncTypes.EDGE_TYPE.equals(entityType)) {
            return Optional.ofNullable(db.select(PINBOARD_EDGE.PAGE_ID)
                    .from(PINBOARD_EDGE)
                    .where(PINBOARD_EDGE.ID.eq(entityId))
                    .fetchOne(PINBOARD_EDGE.PAGE_ID));
        }
        return Optional.empty();
    }
}
