package de.danielkononov.hiwiski.sync;

import java.util.Map;
import java.util.UUID;

/**
 * Fields of a mutation were discarded because someone else has changed them in the
 * meantime.
 *
 * <p>The path for a module that wants to keep the losing version without {@code sync}
 * knowing it — for the wiki text that is the revision with {@code kind = CONFLICT}. An
 * event like {@link EntityWritten}, and therefore only after the commit: a conflict
 * revision for a mutation that rolled back would be a version that never existed.
 *
 * @param rejected the discarded fields with the values the device wanted to write
 * @param fields all fields of the mutation, including the accepted ones
 */
public record FieldsRejected(
        String entityType, UUID entityId, UUID actor, Map<String, Object> rejected, Map<String, Object> fields) {}
