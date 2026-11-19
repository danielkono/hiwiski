package de.danielkononov.hiwiski.access;

/**
 * The three levels.
 *
 * <p>There are no more. An earlier version had 23 permissions, four roles and a role editor; what
 * was needed was the question "who sees this".
 */
public enum AccessLevel {

    /** See, search, comment, link. */
    READ,

    /**
     * Additionally: toggle a task's status and check off occurrences of a series.
     * <strong>Nothing else</strong> -- no title, no date, no deleting.
     *
     * <p>This level is not optional: the design requires it on the wall tablet and on the
     * kids' shopping list. With only <em>read</em> and <em>write</em> this cannot be
     * expressed -- either the tablet can do nothing, or it can delete the list.
     */
    CHECK,

    /**
     * Additionally: create, change, delete within the container.
     *
     * <p><strong>Not:</strong> change the share or delete the container. Only the owner
     * may do that.
     */
    WRITE;

    /** Whether this level allows at least as much as the other. */
    public boolean atLeast(AccessLevel other) {
        return ordinal() >= other.ordinal();
    }

    public static AccessLevel parse(String value) {
        for (AccessLevel level : values()) {
            if (level.name().equals(value)) {
                return level;
            }
        }
        return READ;
    }
}
