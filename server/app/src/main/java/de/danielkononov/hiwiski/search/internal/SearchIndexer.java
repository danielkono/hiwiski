package de.danielkononov.hiwiski.search.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.SEARCH_INDEX;

import de.danielkononov.hiwiski.platform.ChangeSequence;
import de.danielkononov.hiwiski.platform.CoveredWrites;
import de.danielkononov.hiwiski.search.Searchable;
import de.danielkononov.hiwiski.sync.EntityWritten;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import org.jooq.DSLContext;
import de.danielkononov.hiwiski.admin.InstanceRestored;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

/**
 * Updates the index after every change.
 *
 * <p><strong>Maintained on write, not on search.</strong> A search that goes across all
 * domain tables at runtime has to know every type — exactly the enumeration the module
 * inversion avoids. And it would be slow.
 *
 * <p>{@code @ApplicationModuleListener}: after the commit, in a transaction of its own,
 * recorded in {@code event_publication}. A restart in the middle of the follow-up does
 * not lose it, and an indexing error does not bring down the mutation.
 */
@Component
class SearchIndexer {

    private final DSLContext db;
    private final Map<String, Searchable> sources;

    /**
     * The items rebuilt for what depends on them, by type and id. Once for writes that
     * come together: a page deleted or brought back with the thousand elements of its
     * pinboard rebuilt its entry -- reading the whole map -- for each of them.
     */
    private final CoveredWrites<String> dependents;

    SearchIndexer(DSLContext db, List<Searchable> sources, ChangeSequence sequence) {
        this.db = db;
        this.sources = sources.stream()
                .collect(java.util.stream.Collectors.toMap(Searchable::itemType, Function.identity()));
        this.dependents = new CoveredWrites<>(sequence);
    }

    @ApplicationModuleListener
    void onEntityWritten(EntityWritten event) {
        reindex(event.entityType(), event.entityId());
        // What depends on it: the tasks of a list that was just archived or restored.
        for (Searchable source : sources.values()) {
            for (UUID affected : source.affectedBy(event.entityType(), event.entityId())) {
                dependents.run(
                        source.itemType() + ":" + affected,
                        event.version(),
                        () -> reindex(source.itemType(), affected));
            }
        }
    }

    /**
     * Rebuilds the whole index.
     *
     * <p>After a restore: the index does not belong in the archive — it is derived and
     * only makes it bigger. But afterwards it has to be in place again, otherwise search
     * finds nothing until someone happens to change something.
     *
     * <p>The list of items comes from {@code effective_access}: it holds every item that
     * anyone may see — and that is all of them. No module has to register additionally
     * for this.
     */
    /**
     * After a backup restore: the index is not in the archive, and the restore emptied
     * it along with the members. Until now nothing listened, and every search came back
     * empty until each item happened to be edited again.
     */
    @ApplicationModuleListener
    void onInstanceRestored(InstanceRestored event) {
        reindexAll();
    }

    int reindexAll() {
        var items = db.selectDistinct(
                        de.danielkononov.hiwiski.db.generated.Tables.EFFECTIVE_ACCESS.ITEM_TYPE,
                        de.danielkononov.hiwiski.db.generated.Tables.EFFECTIVE_ACCESS.ITEM_ID)
                .from(de.danielkononov.hiwiski.db.generated.Tables.EFFECTIVE_ACCESS)
                .fetch();

        int count = 0;
        for (var item : items) {
            if (sources.containsKey(item.value1())) {
                reindex(item.value1(), item.value2());
                count++;
            }
        }
        return count;
    }

    void reindex(String itemType, UUID itemId) {
        var source = sources.get(itemType);
        if (source == null) {
            return;
        }

        // One reindex of an item at a time: the listener that read the older row and
        // committed last left the old title in the index.
        db.execute("select pg_advisory_xact_lock(hashtextextended({0}, 0))", "search:" + itemType + ":" + itemId);
        var entry = source.entryOf(itemId).orElse(null);
        if (entry == null) {
            // Deleted or no longer indexable: the entry has to go, otherwise search
            // would find something that no longer exists.
            db.deleteFrom(SEARCH_INDEX)
                    .where(SEARCH_INDEX.ITEM_TYPE.eq(itemType))
                    .and(SEARCH_INDEX.ITEM_ID.eq(itemId))
                    .execute();
            return;
        }

        db.insertInto(SEARCH_INDEX)
                .set(SEARCH_INDEX.ITEM_TYPE, itemType)
                .set(SEARCH_INDEX.ITEM_ID, itemId)
                .set(SEARCH_INDEX.OWNER_ID, entry.ownerId())
                .set(SEARCH_INDEX.TITLE, entry.title() == null ? "" : entry.title())
                .set(SEARCH_INDEX.BODY, entry.body() == null ? "" : entry.body())
                .set(SEARCH_INDEX.ENTITY_KEY, entry.entityKey())
                .set(SEARCH_INDEX.CONTEXT, entry.context())
                .set(SEARCH_INDEX.ARCHIVED, entry.archived())
                .set(SEARCH_INDEX.UPDATED_AT, java.time.OffsetDateTime.now())
                .onConflict(SEARCH_INDEX.ITEM_TYPE, SEARCH_INDEX.ITEM_ID)
                .doUpdate()
                .set(SEARCH_INDEX.OWNER_ID, entry.ownerId())
                .set(SEARCH_INDEX.TITLE, entry.title() == null ? "" : entry.title())
                .set(SEARCH_INDEX.BODY, entry.body() == null ? "" : entry.body())
                .set(SEARCH_INDEX.ENTITY_KEY, entry.entityKey())
                .set(SEARCH_INDEX.CONTEXT, entry.context())
                .set(SEARCH_INDEX.ARCHIVED, entry.archived())
                .set(SEARCH_INDEX.UPDATED_AT, java.time.OffsetDateTime.now())
                .execute();
    }
}
