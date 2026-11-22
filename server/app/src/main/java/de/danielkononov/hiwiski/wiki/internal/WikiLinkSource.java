package de.danielkononov.hiwiski.wiki.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_PAGE;

import de.danielkononov.hiwiski.link.LinkSource;
import java.util.Optional;
import java.util.UUID;
import org.jooq.DSLContext;
import org.springframework.stereotype.Component;

/** What {@code wiki} registers with {@code link}. */
@Component
class WikiLinkSource implements LinkSource {

    private final DSLContext db;
    private final MindmapTexts mindmaps;

    WikiLinkSource(DSLContext db, MindmapTexts mindmaps) {
        this.db = db;
        this.mindmaps = mindmaps;
    }

    @Override
    public String itemType() {
        return WikiSyncTypes.PAGE_TYPE;
    }

    @Override
    public String textOf(UUID itemId) {
        String content = db.select(WIKI_PAGE.CONTENT)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.ID.eq(itemId))
                .fetchOne(WIKI_PAGE.CONTENT);
        // A link on the page's mind map is a link from the page.
        String map = mindmaps.of(itemId);
        return map.isEmpty() || content == null ? content : content + "\n" + map;
    }

    @Override
    public Optional<String> titleOf(UUID itemId) {
        return Optional.ofNullable(db.select(WIKI_PAGE.TITLE)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.ID.eq(itemId))
                .and(WIKI_PAGE.DELETED_AT.isNull())
                .fetchOne(WIKI_PAGE.TITLE));
    }

    @Override
    public Optional<UUID> byEntityKey(String entityKey) {
        return Optional.ofNullable(db.select(WIKI_PAGE.ID)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.ENTITY_KEY.eq(entityKey))
                .and(WIKI_PAGE.DELETED_AT.isNull())
                .fetchOne(WIKI_PAGE.ID));
    }

    @Override
    public Optional<String> entityKeyOf(UUID itemId) {
        return Optional.ofNullable(db.select(WIKI_PAGE.ENTITY_KEY)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.ID.eq(itemId))
                .fetchOne(WIKI_PAGE.ENTITY_KEY));
    }
}
