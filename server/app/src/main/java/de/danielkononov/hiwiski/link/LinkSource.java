package de.danielkononov.hiwiski.link;

import java.util.Optional;
import java.util.UUID;

/**
 * What a domain module contributes to references: which field the text comes from and
 * what a target is called.
 *
 * <p>The same inversion as with {@code sync}, {@code access} and {@code admin}:
 * {@code link} does not enumerate domain types.
 */
public interface LinkSource {

    String itemType();

    /** The text references are parsed from — or empty if there is none. */
    String textOf(UUID itemId);

    /**
     * The <strong>current</strong> title of a target, for the chip.
     *
     * <p>Not the text that applied when it was written: a reference shows what is there
     * now.
     */
    Optional<String> titleOf(UUID itemId);

    /** The identifier under which an item is cited as {@code #WIKI-3}. */
    default Optional<UUID> byEntityKey(String entityKey) {
        return Optional.empty();
    }

    /**
     * This item's number — the mono number in the info bar.
     *
     * <p>Empty as long as none is assigned: an item created offline does not have one
     * yet, and an imported event never gets one.
     */
    default Optional<String> entityKeyOf(UUID itemId) {
        return Optional.empty();
    }
}
