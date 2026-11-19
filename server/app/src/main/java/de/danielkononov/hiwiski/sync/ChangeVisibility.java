package de.danielkononov.hiwiski.sync;

import java.util.UUID;
import org.jooq.Condition;
import org.jooq.Field;

/**
 * Whether a member may see a log entry.
 *
 * <p><strong>{@code access} points to {@code sync}, not the other way round.</strong>
 * {@code sync} needs a visibility check to filter the log and declares it here as an
 * interface; {@code access} implements it and in turn writes share changes to the log.
 * The other way round would be a cycle.
 *
 * <p>The condition goes <strong>into the same query</strong> as the results. Two steps
 * would be a time window, and even the existence of an item is information.
 */
public interface ChangeVisibility {

    /**
     * The condition appended to the log query.
     *
     * @param memberId who is reading
     */
    Condition visibleTo(UUID memberId);

    /**
     * The same check for a row of the entity table -- for the snapshot that delivers the
     * state instead of the log.
     *
     * @param memberId who is reading
     * @param entityType the type of the rows
     * @param itemId the column holding their ID
     */
    Condition itemVisibleTo(UUID memberId, String entityType, Field<UUID> itemId);

    /** Whether this member sees this item at all -- owns it or has a level on it. */
    boolean maySee(UUID memberId, String entityType, UUID entityId);

    /**
     * Whether this member may write this item.
     *
     * <p>The client is never the authority: offline, the app may optimistically allow
     * what it may do as far as it last knew. The server checks again on push and rejects
     * if necessary.
     *
     * @param containerType the type of the container -- for a comment, of its carrier
     */
    boolean mayWrite(UUID memberId, String entityType, UUID entityId, String containerType, UUID containerId);

    /**
     * Whether this member may put an item of this type into this container -- the check a
     * new item needs, and an existing one that moves.
     *
     * <p>Without it, whoever may write an item could move it into any list or page and
     * thereby hand it to that container's audience, whatever their access there.
     *
     * @param containerId the target container, or {@code null} for none
     */
    boolean mayPlaceIn(UUID memberId, String entityType, UUID containerId);

    /**
     * Whether this member may write this <em>field</em>.
     *
     * <p>The <em>check off</em> level exists only because the design asks for it in two
     * places — the wall tablet and children at the shopping list. It allows exactly the
     * status and nothing else; without a per-field check it could not be expressed, and
     * the tablet could either do nothing or delete the list.
     *
     * @return whether the field may be written; otherwise it drops out of the mutation
     */
    boolean mayWriteField(UUID memberId, String entityType, UUID entityId, String field);

    /**
     * Whether this member may delete this item.
     *
     * <p>Stricter than {@link #mayWrite}: <em>check off</em> passes that gate to tick a box,
     * but "no deleting" is part of the level's definition.
     */
    boolean mayDelete(UUID memberId, String entityType, UUID entityId);

    /**
     * Whether this member may delete an item that would go along with deleting
     * {@code rootType}/{@code rootId} -- a task with its list, a subpage with its page.
     *
     * <p>A delete takes everything with it, including what the member cannot see. Without
     * this question <em>write</em> on a page deleted a subpage someone had shared with
     * others only, and a subscription in someone else's calendar took that calendar along.
     */
    boolean mayDeleteAlong(UUID memberId, String rootType, UUID rootId, String entityType, UUID entityId);

    /**
     * After a write.
     *
     * <p>The share of a freshly created item must be in place <strong>before</strong> the
     * next pull runs — otherwise the owner would not see their own item. An event after
     * the commit could not do that: it would be a time window.
     *
     * <p>That is why the callback lives here and not as a dependency of {@code sync} on
     * {@code access} — that would be a cycle.
     *
     * @param created the write brought the item into being. Its creation is in the log
     *     with all its fields, and everyone who may see it pulls it from there — unlike an
     *     item that becomes visible to someone later, whose history lies before their
     *     position.
     * @param chosen the fields the actor's own mutation wrote, each with the value it had
     *     before (null for a new item). Empty for a server write -- an import, a
     *     subscription's refresh or a restore from the trash writes in someone's name, but
     *     chooses nothing for them. Assignment reads it: only what the owner's own
     *     mutation assigns is the owner's choice.
     */
    void onEntityWritten(
            String entityType, UUID entityId, UUID actor, boolean created, java.util.Map<String, Object> chosen);
}
