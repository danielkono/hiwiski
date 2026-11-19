package de.danielkononov.hiwiski.search;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.function.BiPredicate;

/**
 * What a domain module contributes to search.
 *
 * <p>The same inversion as with {@code sync}, {@code access}, {@code admin} and
 * {@code link}: {@code search} does not enumerate domain types.
 */
public interface Searchable {

    String itemType();

    /** What of this item belongs in the index — or empty if it is deleted. */
    Optional<Entry> entryOf(UUID itemId);

    /**
     * Other items of this type whose entry depends on the one just written.
     *
     * <p>A task counts as archived when its list is — archiving the list
     * has to update the entries of its tasks, although none of them was written.
     *
     * @param entityType the type of what was written, possibly another one than
     *     {@link #itemType()}
     */
    default List<UUID> affectedBy(String entityType, UUID entityId) {
        return List.of();
    }

    /**
     * Where the item was found, as this reader may see it.
     *
     * <p>Resolved when the hit is shown, not when it is indexed: a task assigned to Ben
     * in Anna's private list "Presents for Ben" is his to find, the list's name is not,
     * and a page shared on its own must not show the private branch above it. Read at
     * index time, the context also went stale when a parent was renamed or moved.
     *
     * @param indexed the context stored with the entry
     * @param visible whether the reader may see an item: type and ID
     * @return the context to show, or {@code null}
     */
    default String contextFor(UUID itemId, String indexed, BiPredicate<String, UUID> visible) {
        return indexed;
    }

    /**
     * @param context where the item was found, as the hit shows it: "Recipes › Autumn
     *     cooking", "Calendar Mum"
     * @param archived left out of search unless asked for
     */
    record Entry(UUID ownerId, String title, String body, String entityKey, String context, boolean archived) {

        public Entry(UUID ownerId, String title, String body, String entityKey, String context) {
            this(ownerId, title, body, entityKey, context, false);
        }
    }
}
