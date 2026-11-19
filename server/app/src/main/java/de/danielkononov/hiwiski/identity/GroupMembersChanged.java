package de.danielkononov.hiwiski.identity;

import java.util.List;
import java.util.UUID;

/**
 * The members of these groups changed — someone joined, left, or the group is gone.
 *
 * <p>Shares and assignments name groups, but {@code effective_access} holds members:
 * groups are resolved when access is computed, not when it is read.
 * Without this event a member added to "Parents" later would never see what was shared
 * with "Parents" before. Published inside the transaction that changes the membership,
 * so the access is right by the time it commits.
 */
public record GroupMembersChanged(List<UUID> groupIds) {}
