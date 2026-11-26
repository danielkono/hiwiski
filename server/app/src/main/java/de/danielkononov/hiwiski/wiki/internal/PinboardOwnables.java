package de.danielkononov.hiwiski.wiki.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.PINBOARD_EDGE;
import static de.danielkononov.hiwiski.db.generated.Tables.PINBOARD_NODE;
import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_PAGE;

import de.danielkononov.hiwiski.access.JooqOwnable;
import de.danielkononov.hiwiski.access.Ownable;
import de.danielkononov.hiwiski.admin.JooqRestorable;
import de.danielkononov.hiwiski.admin.Restorable;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.jooq.DSLContext;
import org.jooq.Field;
import org.jooq.Table;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * What a pinboard's elements and connections register with {@code access} and
 * {@code admin}.
 *
 * <p>Their container is their page: they inherit its share, and a moved page takes its
 * map's audience along.
 */
@Configuration
class PinboardOwnables {

    @Bean
    Ownable pinboardNodeOwnable(DSLContext db) {
        return new JooqOwnable(db, PinboardSyncTypes.NODE_TYPE, PINBOARD_NODE, WikiSyncTypes.PAGE_TYPE, PINBOARD_NODE.PAGE_ID);
    }

    @Bean
    Ownable pinboardEdgeOwnable(DSLContext db) {
        return new JooqOwnable(db, PinboardSyncTypes.EDGE_TYPE, PINBOARD_EDGE, WikiSyncTypes.PAGE_TYPE, PINBOARD_EDGE.PAGE_ID);
    }

    @Bean
    Restorable pinboardNodeRestorable(DSLContext db) {
        return new ElementsOfAPage(db, PinboardSyncTypes.NODE_TYPE, PINBOARD_NODE, PINBOARD_NODE.PAGE_ID);
    }

    @Bean
    Restorable pinboardEdgeRestorable(DSLContext db) {
        return new ElementsOfAPage(db, PinboardSyncTypes.EDGE_TYPE, PINBOARD_EDGE, PINBOARD_EDGE.PAGE_ID);
    }

    /**
     * Removed for good after the retention period like everything deleted, but never
     * listed in the trash: an element deleted on the canvas is one of hundreds, and one
     * that went with its page comes back with the page.
     */
    private static final class ElementsOfAPage extends JooqRestorable {

        ElementsOfAPage(DSLContext db, String itemType, Table<?> table, Field<UUID> pageColumn) {
            super(db, itemType, table, null, null, pageColumn, WIKI_PAGE);
        }

        @Override
        public List<Deleted> deleted(Instant notBefore) {
            return List.of();
        }

        /**
         * Not in the trash, so not restored from it either: asked for by its id, an
         * element came back on a page that is gone, or a connection to an element that
         * is -- a restore checks none of what a push does.
         */
        @Override
        public Optional<UUID> deletedOwnerOf(UUID itemId) {
            return Optional.empty();
        }
    }
}
