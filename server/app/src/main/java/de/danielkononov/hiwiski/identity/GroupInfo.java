package de.danielkononov.hiwiski.identity;

import java.util.List;
import java.util.UUID;

/**
 * A group: a freely named set of members.
 *
 * <p>It serves <strong>only sharing</strong>, not permissions, and therefore carries no
 * role. When sharing, it is stored <em>as a reference</em> and not
 * resolved into members: whoever joins the group later is included -- that is the point
 * of a group, and whoever expands it at share time builds a list that goes stale.
 */
public record GroupInfo(UUID id, String name, String iconToken, int position, List<UUID> memberIds) {}
