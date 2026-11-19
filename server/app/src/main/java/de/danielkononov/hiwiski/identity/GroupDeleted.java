package de.danielkononov.hiwiski.identity;

import java.util.UUID;

/**
 * A group is gone.
 *
 * <p>Published inside the transaction that deletes it, so whatever was shared with the
 * group is taken away -- and its share rows removed -- by the time it commits.
 */
public record GroupDeleted(UUID groupId) {}
