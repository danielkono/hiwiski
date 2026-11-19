package de.danielkononov.hiwiski.admin.internal;

import java.time.Instant;
import org.jspecify.annotations.Nullable;

/**
 * The manifest inside the encrypted payload -- the first entry of the zip, so a preview
 * reads it without decrypting the photos behind it.
 *
 * <p>This, not the header, decides on restore: the header can be read and changed by
 * anyone with the file, the manifest only by whoever holds the key.
 *
 * @param familyId whose archive this is
 * @param serverVersion the version whose data this is -- for a backup before an update,
 *     the version before it
 */
record Manifest(
        String id,
        Instant createdAt,
        String serverVersion,
        String schemaVersion,
        int members,
        @Nullable String familyName,
        String familyId) {}
