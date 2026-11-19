package de.danielkononov.hiwiski.sync;

import java.util.UUID;

/**
 * An item was written — by a device or by the server.
 *
 * <p>The path for everything that has to happen <em>after</em> a change without
 * {@code sync} knowing the receiver: re-parse references, update a search row.
 * {@link ChangeVisibility} stays alongside, because visibility has to be right
 * <strong>in the same transaction</strong> — an event would be too late there.
 *
 * <p>There is a reason it is an event and not an interface: several can listen, and
 * none of them may hold up the write.
 *
 * @param actor who wrote it; {@code null} if the server did it itself
 * @param byServer the server wrote it -- an import, a fetch result -- not a device. A
 *     listener that answers a device's change with a server write of its own (the first
 *     fetch of a new subscription) must not answer its own write again.
 * @param version the item's version this write produced, or 0 where it is not known. A
 *     listener runs after the commit and possibly after later writes: whoever needs the
 *     item as this write left it reads it at this version ({@link ChangeHistory}), not as
 *     it is by then.
 */
public record EntityWritten(
        String entityType, UUID entityId, UUID actor, boolean deleted, boolean byServer, long version) {

    /** A change a device made. */
    public EntityWritten(String entityType, UUID entityId, UUID actor, boolean deleted) {
        this(entityType, entityId, actor, deleted, false, 0);
    }

    public EntityWritten(String entityType, UUID entityId, UUID actor, boolean deleted, boolean byServer) {
        this(entityType, entityId, actor, deleted, byServer, 0);
    }
}
