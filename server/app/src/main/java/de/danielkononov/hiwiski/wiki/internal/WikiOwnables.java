package de.danielkononov.hiwiski.wiki.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_PAGE;

import de.danielkononov.hiwiski.access.JooqOwnable;
import de.danielkononov.hiwiski.access.Ownable;
import de.danielkononov.hiwiski.admin.JooqRestorable;
import de.danielkononov.hiwiski.admin.Restorable;
import org.jooq.DSLContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * What {@code wiki} registers with {@code access} and {@code admin}.
 *
 * <p>A page's container is its <em>parent page</em> — so the share is inherited down the
 * branch, to any depth, and a moved branch inherits the share of its new place.
 * A share of its own on a subpage overrides the inherited one and
 * survives the move.
 */
@Configuration
class WikiOwnables {

    @Bean
    Ownable wikiPageOwnable(DSLContext db) {
        return new JooqOwnable(
                db, WikiSyncTypes.PAGE_TYPE, WIKI_PAGE, WikiSyncTypes.PAGE_TYPE, WIKI_PAGE.PARENT_ID);
    }

    @Bean
    Restorable wikiPageRestorable(DSLContext db) {
        return new JooqRestorable(
                db,
                WikiSyncTypes.PAGE_TYPE,
                WIKI_PAGE,
                WIKI_PAGE.TITLE,
                WIKI_PAGE.ENTITY_KEY,
                // A page's container is its parent page -- the same table.
                WIKI_PAGE.PARENT_ID,
                WIKI_PAGE);
    }
}
