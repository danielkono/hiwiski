package de.danielkononov.hiwiski.sync;

import java.util.UUID;

/**
 * Writing share changes to the change log.
 *
 * <p>Sync runs on a sequence number. If someone gets access today to a calendar that was
 * filled last month, those changes lie <strong>before</strong> their position — they
 * would never get them. That is why {@code access} writes a synthetic entry on a share,
 * on which the client pulls the container again in full; and on revocation one on which
 * it deletes the local data of that container.
 *
 * <p>{@code access} thereby points to {@code sync} — the permitted direction.
 */
public interface SyntheticChanges {

    /**
     * @param op {@code access_granted} or {@code access_revoked}
     * @param recipient who gains or loses the share; the entry goes only to them,
     *     otherwise others would learn who was shared what
     */
    void append(long seq, String op, String itemType, UUID itemId, UUID recipient);
}
