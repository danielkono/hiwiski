package de.danielkononov.hiwiski.search.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.EFFECTIVE_ACCESS;
import static de.danielkononov.hiwiski.db.generated.Tables.SEARCH_INDEX;

import de.danielkononov.hiwiski.search.Searchable;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.BiPredicate;
import org.jooq.DSLContext;
import org.jooq.impl.DSL;
import org.springframework.stereotype.Service;

/**
 * The search.
 *
 * <p><strong>Search uses prefix ({@code :*}) and substring matching.</strong> "kin" has
 * to match while typing, and "kinder" has to find "Kinderarzt". No stemmer splits German
 * compounds; <strong>substring hits rank 0, behind everything else</strong>.
 *
 * <p><strong>The share check is in the same query as the results.</strong> Two steps
 * would be a time window, and even a title gives away too much.
 */
@Service
class SearchService {

    /** Enough for a hit list; beyond that, you keep typing. */
    private static final int LIMIT = 50;

    private final DSLContext db;
    private final java.util.Map<String, Searchable> sources;

    SearchService(DSLContext db, List<Searchable> sources) {
        this.db = db;
        this.sources = sources.stream()
                .collect(java.util.stream.Collectors.toMap(Searchable::itemType, java.util.function.Function.identity()));
    }

    /**
     * The hit's context for this reader. The index stores it for everyone, but the
     * access check covers only the hit itself -- not the list or the pages it names.
     */
    private String context(String itemType, UUID itemId, String indexed, BiPredicate<String, UUID> visible) {
        var source = sources.get(itemType);
        if (source == null) {
            return null;
        }
        return source.contextFor(itemId, indexed, visible);
    }

    /**
     * Whether the reader may see an item — each one asked once per search.
     *
     * <p>Hits share their lists and the pages above them: asked per hit and per level of
     * its path, fifty hits made several hundred queries, and a search under load took
     * a quarter of a second.
     */
    private BiPredicate<String, UUID> visibleTo(UUID reader) {
        Map<String, Boolean> known = new HashMap<>();
        return (type, id) -> known.computeIfAbsent(type + '/' + id, key -> db.fetchExists(db.selectOne()
                .from(EFFECTIVE_ACCESS)
                .where(EFFECTIVE_ACCESS.MEMBER_ID.eq(reader))
                .and(EFFECTIVE_ACCESS.ITEM_TYPE.eq(type))
                .and(EFFECTIVE_ACCESS.ITEM_ID.eq(id))));
    }

    record Hit(
            String itemType,
            UUID itemId,
            String title,
            String entityKey,
            String context,
            String snippet,
            double rank,
            boolean archived) {}

    /**
     * @param includeArchived also the archive — off by default: whoever searches wants
     *     what is current
     */
    List<Hit> search(String query, UUID reader, List<String> types, boolean includeArchived) {
        String term = query == null ? "" : query.trim();
        if (term.isEmpty()) {
            return List.of();
        }

        // `to_tsquery` with prefix: "kin" -> "kin:*". Each word separately, ANDed.
        String prefixQuery = java.util.Arrays.stream(term.split("\\s+"))
                .filter(word -> !word.isBlank())
                .map(SearchService::sanitize)
                .filter(word -> !word.isBlank())
                .map(word -> word + ":*")
                .reduce((a, b) -> a + " & " + b)
                .orElse("");

        var document = DSL.field("document", Object.class);
        var tsQuery = DSL.field("to_tsquery('german', {0})", Object.class, DSL.val(prefixQuery));

        var matchesWords = DSL.condition("{0} @@ {1}", document, tsQuery);
        // The substring: "kinder" in "Kinderarzt". `ILIKE` with a trigram index, the
        // term escaped: "100%" or "a_b" are text, not wildcards -- a term of only "%"
        // matched every item.
        var matchesPart = SEARCH_INDEX.TITLE.containsIgnoreCase(term).or(SEARCH_INDEX.BODY.containsIgnoreCase(term));

        var rank = DSL.field("ts_rank({0}, {1})", Double.class, document, tsQuery);

        var query_ = db.select(
                        SEARCH_INDEX.ITEM_TYPE,
                        SEARCH_INDEX.ITEM_ID,
                        SEARCH_INDEX.TITLE,
                        SEARCH_INDEX.ENTITY_KEY,
                        SEARCH_INDEX.CONTEXT,
                        SEARCH_INDEX.BODY,
                        SEARCH_INDEX.ARCHIVED,
                        rank.as("rank"))
                .from(SEARCH_INDEX)
                // **In the same query**: whoever may not see the item never gets it
                // delivered -- not even the title.
                .join(EFFECTIVE_ACCESS)
                .on(EFFECTIVE_ACCESS.ITEM_TYPE.eq(SEARCH_INDEX.ITEM_TYPE))
                .and(EFFECTIVE_ACCESS.ITEM_ID.eq(SEARCH_INDEX.ITEM_ID))
                .and(EFFECTIVE_ACCESS.MEMBER_ID.eq(reader))
                .where(prefixQuery.isBlank() ? matchesPart : matchesWords.or(matchesPart));

        if (types != null && !types.isEmpty()) {
            query_ = query_.and(SEARCH_INDEX.ITEM_TYPE.in(types));
        }
        if (!includeArchived) {
            query_ = query_.and(SEARCH_INDEX.ARCHIVED.isFalse());
        }

        var visible = visibleTo(reader);
        return query_
                // Substring hits have rank 0 and so come after everything else.
                .orderBy(DSL.field("rank").desc(), SEARCH_INDEX.TITLE.asc())
                .limit(LIMIT)
                .fetch()
                .map(row -> new Hit(
                        row.get(SEARCH_INDEX.ITEM_TYPE),
                        row.get(SEARCH_INDEX.ITEM_ID),
                        row.get(SEARCH_INDEX.TITLE),
                        row.get(SEARCH_INDEX.ENTITY_KEY),
                        context(row.get(SEARCH_INDEX.ITEM_TYPE), row.get(SEARCH_INDEX.ITEM_ID),
                                row.get(SEARCH_INDEX.CONTEXT), visible),
                        snippet(row.get(SEARCH_INDEX.BODY), term),
                        row.get("rank", Double.class) == null ? 0 : row.get("rank", Double.class),
                        row.get(SEARCH_INDEX.ARCHIVED)));
    }

    /**
     * A number jumps straight to the item instead of running a full-text search —
     * archived or not: a number someone wrote down has to keep working.
     */
    java.util.Optional<Hit> byEntityKey(String key, UUID reader) {
        var row = db.select(
                        SEARCH_INDEX.ITEM_TYPE,
                        SEARCH_INDEX.ITEM_ID,
                        SEARCH_INDEX.TITLE,
                        SEARCH_INDEX.ENTITY_KEY,
                        SEARCH_INDEX.CONTEXT,
                        SEARCH_INDEX.ARCHIVED)
                .from(SEARCH_INDEX)
                .join(EFFECTIVE_ACCESS)
                .on(EFFECTIVE_ACCESS.ITEM_TYPE.eq(SEARCH_INDEX.ITEM_TYPE))
                .and(EFFECTIVE_ACCESS.ITEM_ID.eq(SEARCH_INDEX.ITEM_ID))
                .and(EFFECTIVE_ACCESS.MEMBER_ID.eq(reader))
                .where(SEARCH_INDEX.ENTITY_KEY.equalIgnoreCase(key.trim()))
                .fetchOne();

        return row == null
                ? java.util.Optional.empty()
                : java.util.Optional.of(new Hit(
                        row.get(SEARCH_INDEX.ITEM_TYPE),
                        row.get(SEARCH_INDEX.ITEM_ID),
                        row.get(SEARCH_INDEX.TITLE),
                        row.get(SEARCH_INDEX.ENTITY_KEY),
                        context(row.get(SEARCH_INDEX.ITEM_TYPE), row.get(SEARCH_INDEX.ITEM_ID),
                                row.get(SEARCH_INDEX.CONTEXT), visibleTo(reader)),
                        null,
                        1,
                        row.get(SEARCH_INDEX.ARCHIVED)));
    }

    /**
     * The snippet: the sentence around the hit.
     *
     * <p>By hand instead of with {@code ts_headline}: the client does its own
     * highlighting (it knows its font sizes), and {@code ts_headline} would deliver HTML
     * that has to pass through an app that does not render HTML.
     */
    private static String snippet(String body, String term) {
        if (body == null || body.isBlank()) {
            return null;
        }
        int at = body.toLowerCase(java.util.Locale.ROOT).indexOf(term.toLowerCase(java.util.Locale.ROOT));
        if (at < 0) {
            return body.length() <= 160 ? body : body.substring(0, 160) + "…";
        }
        int from = Math.max(0, at - 40);
        int to = Math.min(body.length(), at + term.length() + 80);
        return (from > 0 ? "…" : "") + body.substring(from, to) + (to < body.length() ? "…" : "");
    }

    /**
     * What may go into a {@code tsquery}.
     *
     * <p>A user types "Müll & Co." — and {@code to_tsquery} throws a syntax error on
     * {@code &}. A search field that yields a server error on a special character is
     * broken.
     */
    private static String sanitize(String word) {
        return word.replaceAll("[^\\p{L}\\p{N}_]", "");
    }
}
