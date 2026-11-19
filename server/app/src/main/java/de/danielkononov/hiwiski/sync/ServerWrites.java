package de.danielkononov.hiwiski.sync;

import java.util.Map;
import java.util.UUID;

/**
 * Changes the <em>server</em> makes — not a device.
 *
 * <p>The ICS sync fetches events while perhaps no device is online. These changes have
 * to go into the log, otherwise nobody learns of them: the pull reads only the log, and
 * what is not in it does not exist for the devices.
 *
 * <p>The path deliberately uses the same mechanics as a push — sequence number, field
 * versions, log entry — so that there is no second truth about how a change comes about.
 */
public interface ServerWrites {

    /**
     * Creates or updates and writes the log entry.
     *
     * @param actor whose name is on the entry; for a subscription, its owner
     * @return the assigned sequence number, which is also the new version
     */
    long upsert(
            String entityType,
            UUID entityId,
            String containerType,
            UUID containerId,
            Map<String, Object> fields,
            UUID actor);

    /** Soft delete with a log entry. */
    long delete(String entityType, UUID entityId, UUID actor);

    /**
     * Brings a soft-deleted item back, with a log entry that carries all its fields.
     *
     * <p>A device that pulled the delete removed the item; it only gets it back from a
     * change in the log, and that change has to be complete -- the device has nothing
     * left to merge it into.
     *
     * <p>With a target, the item goes into that container instead of its old one -- the
     * way back for an item whose container is gone. The target has to exist and the
     * actor needs what creating an item there needs; otherwise it is not found, so the
     * answer does not reveal what exists.
     *
     * @param targetContainerId the container to put it into, or {@code null} to leave it
     *     where it was
     * @param actor who restored it
     * @return the assigned sequence number, which is also the new version
     */
    long restore(String entityType, UUID entityId, UUID targetContainerId, UUID actor);
}
