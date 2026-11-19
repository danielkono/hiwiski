package de.danielkononov.hiwiski.admin;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * What a domain module contributes to the trash: what of it was deleted and how it comes
 * back.
 *
 * <p>The same inversion as with {@code sync} and {@code access}: {@code admin} does not
 * enumerate domain types.
 */
public interface Restorable {

    String itemType();

    /** Everything that was deleted and is still within the retention period. */
    List<Deleted> deleted(Instant notBefore);

    /**
     * Whether the item's container is gone by now.
     *
     * <p>Restoring it there would be a disappearance with a detour; it needs another
     * container. The restore itself goes through sync, so the devices
     * learn of it like of any other change.
     */
    boolean containerGone(UUID itemId);

    /**
     * The owner of a deleted item -- empty if there is no such item in the trash.
     *
     * <p>Restoring asks the same question as the listing: only the owner or whoever may
     * write the item gets it back.
     */
    Optional<UUID> deletedOwnerOf(UUID itemId);

    /** Remove for good once the retention period has expired. */
    int purgeOlderThan(Instant cutoff);

    /**
     * @param title what the user looks for in the trash -- "Take out the garbage", not a
     *     UUID
     * @param containerGone the container is gone; restoring then asks for a target
     */
    record Deleted(
            UUID itemId,
            UUID ownerId,
            String title,
            String entityKey,
            Instant deletedAt,
            UUID deletedBy,
            boolean containerGone) {}

    /** The title of a single item -- for messages. */
    default Optional<String> titleOf(UUID itemId) {
        return Optional.empty();
    }
}
