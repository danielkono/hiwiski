package de.danielkononov.hiwiski.access;

import java.util.UUID;

/** An item, named without a type: the cross-cutting layer knows no domain types. */
public record ItemRef(String itemType, UUID itemId) {}
