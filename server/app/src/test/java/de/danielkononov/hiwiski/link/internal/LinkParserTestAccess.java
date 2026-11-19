package de.danielkononov.hiwiski.link.internal;

import java.util.List;

/**
 * The way to the package-private implementation without making it public.
 *
 * <p>Nothing public outside the module root package except the interfaces.
 * The golden test needs the parser directly — after all, it tests
 * the parser and not the interface.
 */
public final class LinkParserTestAccess {

    private LinkParserTestAccess() {}

    /**
     * The normalized form from {@code golden/links.json}: {@code key:<KEY>} and
     * {@code uri:<TYPE>/<uuid>}.
     */
    public static List<String> parse(String text) {
        return new LinkParser().parse(text).stream()
                .map(found -> switch (found) {
                    case LinkParser.Found.ByKey key -> "key:" + key.entityKey();
                    case LinkParser.Found.ByUri uri -> "uri:" + uri.itemType() + "/" + uri.itemId();
                })
                .toList();
    }
}
