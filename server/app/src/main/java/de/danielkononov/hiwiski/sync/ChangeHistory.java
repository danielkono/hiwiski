package de.danielkononov.hiwiski.sync;

import java.util.Map;
import java.util.Optional;
import java.util.UUID;

/** What a field of an item was at a given version -- read from the change log. */
public interface ChangeHistory {

    /**
     * The last value written to the field up to and including {@code version}.
     *
     * @return empty if the log has no write of it up to there (never written, or cleaned
     *     up by retention); an entry otherwise, since {@code null} is a value too
     */
    Optional<Map.Entry<String, Object>> valueAt(String entityType, UUID entityId, String field, long version);
}
