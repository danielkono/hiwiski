package de.danielkononov.hiwiski.identity;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * A member, as other modules need it.
 *
 * <p>Without the password hash and without anything that only concerns login -- a domain
 * module looking up the name for an ID has nothing to do with either.
 */
public record MemberInfo(
        UUID id,
        String username,
        String displayName,
        boolean isAdmin,
        String colorToken,
        List<UUID> groupIds,
        Instant createdAt,
        boolean disabled) {}
