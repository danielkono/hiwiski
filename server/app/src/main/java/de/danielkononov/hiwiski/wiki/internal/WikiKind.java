package de.danielkononov.hiwiski.wiki.internal;

import de.danielkononov.hiwiski.platform.KeyedEntityType;
import de.danielkononov.hiwiski.sync.SyncProperty;
import java.util.List;
import java.util.Optional;

/**
 * A kind of wiki page and what it brings beyond title and text: its fields, its range of numbers, the fields that hold an image.
 *
 * <p>All kinds share one table and one entity type — the tree, moving, sharing and
 * history stay one thing. What a kind adds lives in the page's property map: each of
 * its fields is a {@link SyncProperty}, synced and conflict-checked on its own, and
 * needs no column. <strong>A new kind is one bean</strong> next to {@link RecipeKind};
 * nothing else in the server changes.
 */
interface WikiKind {

    /** The page's {@code kind}, as the app writes it — {@code RECIPE}. */
    String code();

    /** The fields only this kind carries. Their names are unique across all kinds. */
    List<SyncProperty> properties();

    /**
     * The range its numbers come from; empty for the wiki's own ({@code WIKI-3}). A
     * range of its own needs an entry in {@link KeyedEntityType} and its counter row.
     */
    default Optional<KeyedEntityType> keyType() {
        return Optional.empty();
    }

    /**
     * The properties that hold the id of an image uploaded for the page — checked to be
     * the page's own, and kept by the weekly cleanup.
     */
    default List<String> imageProperties() {
        return List.of();
    }
}
