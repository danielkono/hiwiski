package de.danielkononov.hiwiski.sync;

import java.util.Map;
import java.util.Set;

/**
 * The two fields that archive an item, and the rule that comes with them.
 *
 * <p>Archiving is an ordinary change through sync, not a place an item moves to.
 * An archived item is read-only: whatever the mutation carries besides
 * these two fields is refused — that is how restoring stays possible while editing does
 * not.
 *
 * <p>It lives here and not in a domain module because two of them need it, wiki and
 * todo, and the rule has to read the same in both.
 */
public final class Archive {

    public static final String ARCHIVED_AT = "archivedAt";
    public static final String ARCHIVED_BY = "archivedBy";

    /** The rejection the client shows — "Archived, read-only". */
    public static final String READ_ONLY = "archive.read_only";

    private static final Set<String> FIELDS = Set.of(ARCHIVED_AT, ARCHIVED_BY);

    private Archive() {}

    /** Who archived it is whoever pushes it, and not later than now ({@link SyncType#stamp}). */
    public static Map<String, Object> stamped(Map<String, Object> fields, java.util.UUID actor, java.time.OffsetDateTime now) {
        return SyncType.stamp(fields, ARCHIVED_BY, ARCHIVED_AT, actor, now);
    }

    /** Whether the mutation only archives or restores and changes nothing else. */
    public static boolean onlyArchiveFields(Map<String, Object> fields) {
        return fields == null || FIELDS.containsAll(fields.keySet());
    }
}
