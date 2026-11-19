package de.danielkononov.hiwiski.identity.internal;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/** A row from {@code member}, together with its groups. */
record MemberRow(
        UUID id,
        String username,
        String displayName,
        String passwordHash,
        boolean mustChangePassword,
        boolean isAdmin,
        String colorToken,
        String themeMode,
        OffsetDateTime createdAt,
        OffsetDateTime disabledAt,
        UUID avatarImageId,
        List<UUID> groupIds) {

    boolean disabled() {
        return disabledAt != null;
    }
}
