package de.danielkononov.hiwiski.admin;

import java.util.UUID;

/**
 * An archive was restored.
 *
 * <p>Everything <em>derived</em> from the domain data has to be rebuilt afterwards —
 * the search index, for instance, is not in the archive, because it would only make it
 * bigger without carrying anything that is not already in it.
 *
 * <p>An event and not a call: {@code admin} does not know {@code search}, and the
 * inversion holds here too.
 *
 * @param instanceId the new identifier — by it the devices recognize that their state
 *     no longer applies
 */
public record InstanceRestored(UUID instanceId) {}
