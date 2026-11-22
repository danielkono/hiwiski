package de.danielkononov.hiwiski.wiki.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_PAGE;

import de.danielkononov.hiwiski.search.Searchable;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.function.BiPredicate;
import org.jooq.DSLContext;
import org.jooq.impl.DSL;
import org.springframework.stereotype.Component;

/** What {@code wiki} registers with {@code search}. */
@Component
class WikiSearchable implements Searchable {

    /** So that a cycle does not become an endless loop. */
    private static final int MAX_DEPTH = 32;

    private final DSLContext db;
    private final MindmapTexts mindmaps;

    WikiSearchable(DSLContext db, MindmapTexts mindmaps) {
        this.db = db;
        this.mindmaps = mindmaps;
    }

    @Override
    public String itemType() {
        return WikiSyncTypes.PAGE_TYPE;
    }

    @Override
    public Optional<Entry> entryOf(UUID itemId) {
        var row = db.select(
                        WIKI_PAGE.OWNER_ID,
                        WIKI_PAGE.TITLE,
                        WIKI_PAGE.CONTENT,
                        WIKI_PAGE.ENTITY_KEY,
                        WIKI_PAGE.PARENT_ID,
                        WIKI_PAGE.ARCHIVED_AT)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.ID.eq(itemId))
                .and(WIKI_PAGE.DELETED_AT.isNull())
                .fetchOne();

        if (row == null) {
            return Optional.empty();
        }
        // A word on the page's mind map finds the page.
        String map = mindmaps.of(itemId);
        return Optional.of(new Entry(
                row.value1(),
                row.value2(),
                map.isEmpty() ? row.value3() : row.value3() + "\n" + map,
                row.value4(),
                // Where it was found, as a path: "Recipes › Autumn cooking".
                breadcrumb(row.value5()),
                row.value6() != null));
    }

    /**
     * The path up to the first page the reader may not see — none of it above that.
     *
     * <p>The pages above in one query, nearest first: one query per level made a search
     * with fifty hits in a deep tree a few hundred queries.
     */
    /** A change on a mind map is one of its page's text. */
    @Override
    public List<UUID> affectedBy(String entityType, UUID entityId) {
        return mindmaps.pageOf(entityType, entityId).stream().toList();
    }

    @Override
    public String contextFor(UUID itemId, String indexed, BiPredicate<String, UUID> visible) {
        var above = db.resultQuery(
                        """
                        with recursive above(id, title, parent_id, depth) as (
                            select p.id, p.title, p.parent_id, 1
                            from wiki_page p
                            where p.id = (select parent_id from wiki_page where id = {0})
                          union all
                            select p.id, p.title, p.parent_id, above.depth + 1
                            from wiki_page p
                            join above on p.id = above.parent_id
                            where above.depth < {1}
                        )
                        select id, title from above order by depth
                        """,
                        DSL.val(itemId),
                        DSL.val(MAX_DEPTH))
                .fetch();
        List<String> trail = new ArrayList<>();
        for (var row : above) {
            UUID page = row.get(0, UUID.class);
            if (!visible.test(itemType(), page)) {
                break;
            }
            trail.addFirst(row.get(1, String.class));
        }
        return trail.isEmpty() ? null : String.join(" › ", trail);
    }

    private String breadcrumb(UUID parentId) {
        List<String> trail = new ArrayList<>();
        UUID current = parentId;
        for (int depth = 0; current != null && depth < MAX_DEPTH; depth++) {
            var row = db.select(WIKI_PAGE.TITLE, WIKI_PAGE.PARENT_ID)
                    .from(WIKI_PAGE)
                    .where(WIKI_PAGE.ID.eq(current))
                    .fetchOne();
            if (row == null) {
                break;
            }
            trail.addFirst(row.value1());
            current = row.value2();
        }
        return trail.isEmpty() ? null : String.join(" › ", trail);
    }
}
