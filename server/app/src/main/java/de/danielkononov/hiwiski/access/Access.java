package de.danielkononov.hiwiski.access;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/** What other modules may know and change about shares. */
public interface Access {

    /** The level this member has on this item -- or none. */
    Optional<AccessLevel> levelOf(UUID memberId, String itemType, UUID itemId);

    default boolean may(UUID memberId, String itemType, UUID itemId, AccessLevel required) {
        return levelOf(memberId, itemType, itemId).filter(level -> level.atLeast(required)).isPresent();
    }

    /**
     * Of these items, the ones this member may at least [required] on — asked at once,
     * for lists that would otherwise ask item by item (the trash).
     */
    default java.util.Set<UUID> mayAll(
            UUID memberId, String itemType, java.util.Collection<UUID> itemIds, AccessLevel required) {
        return itemIds.stream()
                .filter(itemId -> may(memberId, itemType, itemId, required))
                .collect(java.util.stream.Collectors.toSet());
    }

    /**
     * Whether this member may delete this item -- or restore it from the trash.
     *
     * <p>The owner may. Anyone else needs <em>write</em> on the item <strong>and</strong> on
     * the container it lies in: <em>write</em> allows deleting within the container, not
     * deleting the container itself. A list, a calendar, a root page or a
     * board has no container above it, so only its owner deletes it. A comment is deleted
     * by its author only.
     *
     * <p>An item that does not exist (any more) counts as deletable: a delete that finds
     * nothing has arrived.
     */
    boolean mayDelete(UUID memberId, String itemType, UUID itemId);

    /**
     * Recomputes the share of an item -- and that of all items below it.
     *
     * <p>To be called when a share is written or removed, a page is moved, someone joins
     * or leaves a group, or an item is created.
     */
    default void recalculate(String itemType, UUID itemId) {
        recalculate(itemType, itemId, null);
    }

    /**
     * @param cause who triggered the change. Nothing is announced to them — they were
     *     there. Without this exception, everyone who creates something would get an
     *     {@code access_granted} for their own item and then pull the whole container
     *     again: once per creation, for nothing.
     */
    void recalculate(String itemType, UUID itemId, UUID cause);

    /**
     * The share of an item that has just come into being, announced to nobody.
     *
     * <p>Its creation is in the log with all its fields, and the log is delivered
     * filtered by exactly this share — whoever may see the item gets it with the next
     * pull. An {@code access_granted} on top made every other device of the family pull
     * its whole snapshot again, once for every task anyone added to a shared list.
     */
    void establish(String itemType, UUID itemId);

    /** The rows of the share sheet, in the order it shows them. */
    List<Grant> grantsOn(String itemType, UUID itemId);

    /**
     * A row in the share sheet.
     *
     * @param source where it comes from -- owner, direct, inherited, assigned automatically
     * @param inheritedFrom the name of the container it was inherited from
     */
    record Grant(
            SubjectType subjectType,
            UUID subjectId,
            AccessLevel level,
            GrantSource source,
            String inheritedFrom) {}

    enum SubjectType {
        MEMBER,
        GROUP
    }

    enum GrantSource {
        OWNER,
        DIRECT,
        INHERITED,
        ASSIGNED
    }
}
