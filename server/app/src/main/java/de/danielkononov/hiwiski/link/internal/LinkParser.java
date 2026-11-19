package de.danielkononov.hiwiski.link.internal;

import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;
import org.springframework.stereotype.Component;

/**
 * Finds references in a Markdown text.
 *
 * <p>Two notations:
 *
 * <table>
 *   <tr><td>{@code #TD-14}</td><td>typed by hand — the convenient form</td></tr>
 *   <tr><td>{@code [Title](hiwiski://todo/<uuid>)}</td><td>inserted by the picker — the
 *       reliable one</td></tr>
 * </table>
 *
 * <p><strong>The picker always inserts the UUID form</strong>, never the number:
 * otherwise an item just created offline could not be linked, and that is exactly the
 * common case — you create a task and in the same breath write it into a wiki page.
 *
 * <p><strong>The same text is read the same way on the device</strong>: the client draws
 * the chips from it and fills the info bar offline. Both sides test against
 * {@code golden/links.json}.
 */
@Component
class LinkParser {

    private static final String UUID_PATTERN =
            "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}";

    /**
     * Both notations in <strong>one</strong> pattern.
     *
     * <p>Not two passes: then all numbers would come first and all addresses after, and
     * the UI would draw the chips in a different order than they appear in the text.
     *
     * <p>{@code #([A-Z][A-Z0-9]{0,7})-(\d+)} — prefix and number, the way the key is
     * built. Upper case: {@code #td-14} is text someone meant that way, and
     * {@code # Shopping} is a heading.
     *
     * <p>{@code hiwiski://([a-z_]+)/(<uuid>)} — also outside a Markdown bracket.
     *
     * <p>{@code [label](hiwiski://…)} as a whole first, as on the device: the label is
     * display text. A {@code #TD-14} inside it is not a reference of its
     * own -- the server wrote one, the device did not, and backlinks and the offline
     * info bar disagreed. The label may hold escaped brackets, as the picker writes them.
     *
     * <p>The label loop is <strong>possessive</strong>: a greedy group with an alternation
     * recurses once per character in {@code java.util.regex}, and an unclosed {@code [}
     * with some 2,000 characters after it threw {@code StackOverflowError} — the links of
     * that item were never written again. Giving
     * characters back could never find a {@code ]} anyway.
     */
    private static final Pattern REFERENCE = Pattern.compile(
            "\\[(?:\\\\.|[^\\]\\n\\\\])*+\\]\\(hiwiski://(?<labelledType>[a-z_]+)/(?<labelledId>"
                    + UUID_PATTERN + ")\\)"
                    + "|#(?<prefix>[A-Z][A-Z0-9]{0,7})-(?<number>\\d+)"
                    + "|hiwiski://(?<type>[a-z_]+)/(?<id>" + UUID_PATTERN + ")");

    /** The bracket and label of the first alternative — where its scan stops. */
    private static final Pattern LABEL = Pattern.compile("\\[(?:\\\\.|[^\\]\\n\\\\])*+");

    /** A reference found, not yet resolved. */
    sealed interface Found {
        record ByKey(String entityKey) implements Found {}

        record ByUri(String itemType, UUID itemId) implements Found {}
    }

    /**
     * All references, in text order and without duplicates.
     *
     * <p>A {@code LinkedHashSet}, so that the same reference twice yields one row — the
     * table has a unique index on it, and a duplicate entry would be an error on write
     * instead of on read.
     */
    Set<Found> parse(String text) {
        Set<Found> found = new LinkedHashSet<>();
        if (text == null || text.isBlank()) {
            return found;
        }

        // Not find(): it tries the label at every "[", and a line of them costs O(n²).
        // Every "[" up to where such a try stopped stops at the same place and fails the
        // same way, so it is skipped -- as on the device (link_text.dart, LinkScanner).
        var matcher = REFERENCE.matcher(text);
        var label = LABEL.matcher(text);
        int length = text.length();
        int failsUntil = -1;
        int at = 0;
        while (at < length) {
            char first = text.charAt(at);
            boolean candidate = first == '[' ? at >= failsUntil : first == '#' || first == 'h';
            if (!candidate) {
                at++;
                continue;
            }
            if (!matcher.region(at, length).lookingAt()) {
                if (first == '[') {
                    label.region(at, length).lookingAt();
                    failsUntil = label.end();
                }
                at++;
                continue;
            }
            at = matcher.end();
            if (matcher.group("prefix") != null) {
                found.add(new Found.ByKey(matcher.group("prefix") + "-" + matcher.group("number")));
            } else {
                String type = matcher.group("labelledType") != null
                        ? matcher.group("labelledType")
                        : matcher.group("type");
                String id = matcher.group("labelledId") != null ? matcher.group("labelledId") : matcher.group("id");
                parseUuid(id).ifPresent(uuid -> found.add(new Found.ByUri(typeOf(type), uuid)));
            }
        }
        return found;
    }

    /**
     * {@code hiwiski://wiki_page/…} and {@code hiwiski://todo/…} — the address is lower
     * case, the entity type upper case.
     */
    private static String typeOf(String path) {
        return path.toUpperCase(Locale.ROOT);
    }

    private static Optional<UUID> parseUuid(String raw) {
        try {
            return Optional.of(UUID.fromString(raw));
        } catch (IllegalArgumentException e) {
            // A broken address in the text is not a user error to hold against them --
            // it just does not yield a reference.
            return Optional.empty();
        }
    }
}
