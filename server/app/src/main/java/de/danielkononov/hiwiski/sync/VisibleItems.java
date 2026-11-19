package de.danielkononov.hiwiski.sync;

import de.danielkononov.hiwiski.api.model.ChangeEnvelope;
import java.util.List;
import java.util.UUID;
import org.jooq.Condition;

/**
 * The live items a member may see, as a snapshot pull would deliver them to them.
 *
 * <p>Public because the <strong>dashboard at its own address</strong> shows its tiles'
 * content to a wall tablet without a sign-in -- in the owner's name, and
 * {@code dashboard} must not reach into {@code sync.internal}.
 */
public interface VisibleItems {

    /** At most this many items per call: a board's tiles show a handful each. */
    int LIMIT = 2000;

    /**
     * @param memberId whose visibility applies
     * @param entityType the type, as in the contract
     * @param filter which of them, over the type's own table
     * @return in ID order, at most {@link #LIMIT}
     */
    List<ChangeEnvelope> visibleTo(UUID memberId, String entityType, Condition filter);
}
