package de.danielkononov.hiwiski.access;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * What a domain module contributes about ownership and inheritance.
 *
 * <p>This is the inversion the module structure rests on: {@code access} does not
 * enumerate domain types; instead every domain module registers here. The same inversion
 * seven times over is why an earlier version did not have to reach in everywhere when wiki,
 * dashboard and search were added.
 */
public interface Ownable {

    String itemType();

    /** Who created the item. Empty if the item does not exist (any more). */
    Optional<UUID> ownerOf(UUID itemId);

    /**
     * The container this item inherits its share from -- list for task, calendar for
     * event, parent page for subpage.
     */
    default Optional<ItemRef> containerOf(UUID itemId) {
        return Optional.empty();
    }

    /** The type of the container, or empty if this type is one itself. */
    default Optional<String> containerType() {
        return Optional.empty();
    }

    /**
     * Whether this type attaches to items of <em>any</em> type — the comment, for example.
     *
     * <p>Then {@link #containerOf} returns the carrier along with its type, and the
     * cascade asks this type for its items at every container. Creating one then needs
     * read access to the carrier: whoever may read may comment.
     */
    default boolean attachesToAnyType() {
        return false;
    }

    /**
     * All live items of this type in this container.
     *
     * <p>For the cascade: when a list's share changes, it changes for every task in it.
     */
    default List<UUID> inContainer(UUID containerId) {
        return List.of();
    }

    /**
     * All items of this type in this container, <em>deleted ones included</em>.
     *
     * <p>For recomputing the share: a deleted task keeps its access rows for the trash,
     * and they have to follow a change of the list's share like a live task's. Skipped,
     * a writer whose share was revoked kept write on every task deleted before.
     */
    default List<UUID> allInContainer(UUID containerId) {
        return inContainer(containerId);
    }

    /**
     * Who this item is assigned to -- members <em>and</em> groups.
     *
     * <p><strong>Assigning shares automatically.</strong> Whoever assigns a task to Ben
     * shares it with him by doing so. Otherwise someone assigns, and the assignee sees
     * nothing.
     */
    default List<UUID> assigneesOf(UUID itemId) {
        return List.of();
    }

    /**
     * Those of {@link #assigneesOf} the item's owner chose.
     *
     * <p>Only they are shared with by the assignment. An assignee someone else added — a
     * member who may write the list, say — gets the assignment's level only if they see
     * the item anyway: <em>write</em> does not change the sharing, and
     * otherwise assigning oneself kept access after the owner revoked the share.
     */
    default List<UUID> ownerAssigneesOf(UUID itemId) {
        return assigneesOf(itemId);
    }

    /**
     * The synced field that holds {@link #assigneesOf} -- {@code assignees} on a task,
     * {@code attendees} on an event. Empty for a type whose assignees are all the owner's
     * anyway, or that has none.
     */
    default Optional<String> assigneeField() {
        return Optional.empty();
    }

    /**
     * After every write of an item: keeps {@link #ownerAssigneesOf} in step with the
     * assignees. The owner's choices become those they had chosen plus {@code
     * chosenByOwner}, of which only those still assigned stay.
     *
     * @param chosenByOwner the assignees the owner's own mutation added -- empty for any
     *     write that does not carry the assignee field, by someone else, or by the server.
     *     Taking every current assignee on any write of the owner turned a writer's
     *     assignment into the owner's the moment the owner ticked the task off.
     */
    default void assignmentWritten(UUID itemId, java.util.Collection<UUID> chosenByOwner) {}

    /**
     * Whether items of this type can be shared at all.
     *
     * <p>Not a board, its tiles, a calendar feed or a member's list order: they belong to
     * one member. A board's or feed's token is a restricted session of its owner, and
     * whoever the board was shared with got that token through sync and with it
     * everything the owner may see.
     */
    default boolean shareable() {
        return true;
    }

    /**
     * The level that creates or deletes an item of this type in its container --
     * <em>write</em>, except where creating one is how its container is ticked off.
     *
     * <p>A checked-off occurrence of a repeating task is a row of its own; <em>check
     * off</em> on the task has to create it and, unticked, delete it, or the level could
     * not tick off a series at all.
     */
    default AccessLevel placementLevel() {
        return AccessLevel.WRITE;
    }

    /**
     * Whether only the container's owner places an item of this type in it, whatever
     * others may write there. A calendar subscription fills its calendar in its creator's
     * name and, deleted, takes the calendar along: one that a writer attached to someone
     * else's calendar could be removed only together with that calendar.
     */
    default boolean placedByContainerOwnerOnly() {
        return false;
    }

    /**
     * Whether an item of this type carries its owner's member id as its own id -- a
     * member's list order, one per member. Then only that member may create it: taken
     * first by someone else, the real member's pushes were refused for good.
     */
    default boolean idIsOwner() {
        return false;
    }

    /**
     * The fields only the owner may write, whatever the share says.
     *
     * <p>A list's assignees get <em>write</em> on the list: assigning one is sharing it,
     * and sharing is the owner's.
     */
    default java.util.Set<String> ownerOnlyFields() {
        return java.util.Set.of();
    }

    /**
     * All live items of this type assigned to this member or group — the reverse of
     * {@link #assigneesOf}.
     *
     * <p>For a change of group membership: an assignment to "Parents" has to reach whoever
     * joins "Parents" later.
     */
    default List<UUID> assignedTo(UUID subject) {
        return List.of();
    }

    /**
     * Whether something can be ticked on this type — only then does <em>check off</em>
     * mean anything. On a calendar or a page it would be <em>read</em> under another name.
     */
    default boolean checkable() {
        return false;
    }

    /** The level an assignment grants: <em>check off</em> for tasks, <em>read</em> for events. */
    default AccessLevel assignmentLevel() {
        return AccessLevel.READ;
    }

    /** All live items of this type that belong to this member. */
    List<UUID> ownedBy(UUID memberId);
}
