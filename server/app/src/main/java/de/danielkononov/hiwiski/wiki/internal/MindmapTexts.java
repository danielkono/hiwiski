package de.danielkononov.hiwiski.wiki.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.MINDMAP_EDGE;
import static de.danielkononov.hiwiski.db.generated.Tables.MINDMAP_NODE;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.jooq.DSLContext;
import org.springframework.stereotype.Component;

/**
 * What a mind map says, as text: the texts of its elements, the items its link elements
 * point to, and the labels of its connections.
 *
 * <p>Counted as part of its page. A reference in an element is one from the page -- the
 * item it points to says "the mind map X links here" -- and a search finds the page by
 * a word on its canvas. An element is no item a person cites or finds on its own.
 */
@Component
class MindmapTexts {

    /** The elements that point to an item. */
    private static final String LINK_KIND = "LINK";

    private final DSLContext db;

    MindmapTexts(DSLContext db) {
        this.db = db;
    }

    /** The map's texts, one per line, in the order the elements were created. */
    String of(UUID pageId) {
        List<String> lines = new ArrayList<>();
        db.select(MINDMAP_NODE.TEXT, MINDMAP_NODE.TARGET, MINDMAP_NODE.KIND)
                .from(MINDMAP_NODE)
                .where(MINDMAP_NODE.PAGE_ID.eq(pageId))
                .and(MINDMAP_NODE.DELETED_AT.isNull())
                .orderBy(MINDMAP_NODE.ID)
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
        db.select(MINDMAP_EDGE.TEXT)
                .from(MINDMAP_EDGE)
                .where(MINDMAP_EDGE.PAGE_ID.eq(pageId))
                .and(MINDMAP_EDGE.DELETED_AT.isNull())
                .and(MINDMAP_EDGE.TEXT.ne(""))
                .orderBy(MINDMAP_EDGE.ID)
                .forEach(row -> lines.add(row.value1()));
        return String.join("\n", lines);
    }

    /** The page an element or a connection is on -- empty for anything else. */
    Optional<UUID> pageOf(String entityType, UUID entityId) {
        if (MindmapSyncTypes.NODE_TYPE.equals(entityType)) {
            return Optional.ofNullable(db.select(MINDMAP_NODE.PAGE_ID)
                    .from(MINDMAP_NODE)
                    .where(MINDMAP_NODE.ID.eq(entityId))
                    .fetchOne(MINDMAP_NODE.PAGE_ID));
        }
        if (MindmapSyncTypes.EDGE_TYPE.equals(entityType)) {
            return Optional.ofNullable(db.select(MINDMAP_EDGE.PAGE_ID)
                    .from(MINDMAP_EDGE)
                    .where(MINDMAP_EDGE.ID.eq(entityId))
                    .fetchOne(MINDMAP_EDGE.PAGE_ID));
        }
        return Optional.empty();
    }
}
