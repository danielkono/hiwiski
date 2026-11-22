package de.danielkononov.hiwiski.wiki.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.MINDMAP_EDGE;
import static de.danielkononov.hiwiski.db.generated.Tables.MINDMAP_NODE;
import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_PAGE;

import de.danielkononov.hiwiski.access.JooqOwnable;
import de.danielkononov.hiwiski.access.Ownable;
import de.danielkononov.hiwiski.admin.JooqRestorable;
import de.danielkononov.hiwiski.admin.Restorable;
import java.time.Instant;
import java.util.List;
import org.jooq.DSLContext;
import org.jooq.Field;
import org.jooq.Table;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * What a mind map's elements and connections register with {@code access} and
 * {@code admin}.
 *
 * <p>Their container is their page: they inherit its share, and a moved page takes its
 * map's audience along.
 */
@Configuration
class MindmapOwnables {

    @Bean
    Ownable mindmapNodeOwnable(DSLContext db) {
        return new JooqOwnable(db, MindmapSyncTypes.NODE_TYPE, MINDMAP_NODE, WikiSyncTypes.PAGE_TYPE, MINDMAP_NODE.PAGE_ID);
    }

    @Bean
    Ownable mindmapEdgeOwnable(DSLContext db) {
        return new JooqOwnable(db, MindmapSyncTypes.EDGE_TYPE, MINDMAP_EDGE, WikiSyncTypes.PAGE_TYPE, MINDMAP_EDGE.PAGE_ID);
    }

    @Bean
    Restorable mindmapNodeRestorable(DSLContext db) {
        return new ElementsOfAPage(db, MindmapSyncTypes.NODE_TYPE, MINDMAP_NODE, MINDMAP_NODE.PAGE_ID);
    }

    @Bean
    Restorable mindmapEdgeRestorable(DSLContext db) {
        return new ElementsOfAPage(db, MindmapSyncTypes.EDGE_TYPE, MINDMAP_EDGE, MINDMAP_EDGE.PAGE_ID);
    }

    /**
     * Removed for good after the retention period like everything deleted, but never
     * listed in the trash: an element deleted on the canvas is one of hundreds, and one
     * that went with its page comes back with the page.
     */
    private static final class ElementsOfAPage extends JooqRestorable {

        ElementsOfAPage(DSLContext db, String itemType, Table<?> table, Field<java.util.UUID> pageColumn) {
            super(db, itemType, table, null, null, pageColumn, WIKI_PAGE);
        }

        @Override
        public List<Deleted> deleted(Instant notBefore) {
            return List.of();
        }
    }
}
