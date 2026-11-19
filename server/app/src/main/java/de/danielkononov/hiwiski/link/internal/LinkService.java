package de.danielkononov.hiwiski.link.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.LINK;

import de.danielkononov.hiwiski.access.Access;
import de.danielkononov.hiwiski.access.AccessLevel;
import de.danielkononov.hiwiski.link.LinkSource;
import de.danielkononov.hiwiski.link.Links;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Function;
import org.jooq.DSLContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * References: parsed, resolved, readable in both directions.
 *
 * <p><strong>What the reader may not see drops out entirely</strong> instead of showing
 * "access denied" — even existence is information.
 */
@Service
class LinkService implements Links {

    private final DSLContext db;
    private final LinkParser parser;
    private final Access access;
    private final Map<String, LinkSource> sources;

    LinkService(DSLContext db, LinkParser parser, Access access, List<LinkSource> sources) {
        this.db = db;
        this.parser = parser;
        this.access = access;
        this.sources = sources.stream()
                .collect(java.util.stream.Collectors.toMap(LinkSource::itemType, Function.identity()));
    }

    @Override
    @Transactional
    public void reparse(String itemType, UUID itemId) {
        var source = sources.get(itemType);
        if (source == null) {
            return;
        }

        // One reparse of an item at a time, until its transaction ends. Two quick saves
        // ran side by side: both deleted, both inserted, and the table held the links of
        // both versions -- a reference removed in the second stayed.
        db.execute("select pg_advisory_xact_lock(hashtextextended({0}, 0))", "link:" + itemType + ":" + itemId);
        var found = parser.parse(source.textOf(itemId));

        // Delete first, then insert anew. A reference that disappears from the text has
        // to disappear -- otherwise the old truth would remain, and that is exactly what
        // "two truths would be one too many" warns against.
        db.deleteFrom(LINK).where(LINK.FROM_TYPE.eq(itemType)).and(LINK.FROM_ID.eq(itemId)).execute();

        // In text order: the first mention of a target decides its place.
        int position = 0;
        for (var entry : found) {
            int at = position++;
            resolve(entry).ifPresent(target -> db.insertInto(LINK)
                    .set(LINK.ID, UUID.randomUUID())
                    .set(LINK.FROM_TYPE, itemType)
                    .set(LINK.FROM_ID, itemId)
                    .set(LINK.TO_TYPE, target.itemType())
                    .set(LINK.TO_ID, target.itemId())
                    .set(LINK.POSITION, at)
                    .onConflictDoNothing()
                    .execute());
        }
    }

    /**
     * Both notations end up in <strong>the same row</strong>, resolved to the UUID.
     */
    private Optional<Target> resolve(LinkParser.Found found) {
        return switch (found) {
            case LinkParser.Found.ByUri uri ->
                sources.containsKey(uri.itemType())
                        ? Optional.of(new Target(uri.itemType(), uri.itemId()))
                        : Optional.empty();
            case LinkParser.Found.ByKey key ->
                sources.values().stream()
                        .flatMap(source -> source.byEntityKey(key.entityKey())
                                .map(id -> new Target(source.itemType(), id))
                                .stream())
                        .findFirst();
        };
    }

    private record Target(String itemType, UUID itemId) {}

    @Override
    public List<Ref> outgoing(String itemType, UUID itemId, UUID reader) {
        return db.select(LINK.TO_TYPE, LINK.TO_ID)
                .from(LINK)
                .where(LINK.FROM_TYPE.eq(itemType))
                .and(LINK.FROM_ID.eq(itemId))
                .orderBy(LINK.POSITION.asc(), LINK.TO_ID.asc())
                .fetch()
                .stream()
                .flatMap(row -> describe(row.value1(), row.value2(), reader).stream())
                .toList();
    }

    @Override
    public List<Ref> incoming(String itemType, UUID itemId, UUID reader) {
        return db.select(LINK.FROM_TYPE, LINK.FROM_ID)
                .from(LINK)
                .where(LINK.TO_TYPE.eq(itemType))
                .and(LINK.TO_ID.eq(itemId))
                .fetch()
                .stream()
                .flatMap(row -> describe(row.value1(), row.value2(), reader).stream())
                // Where it is cited from has no text order: by title, the same every time.
                .sorted(java.util.Comparator.comparing(Ref::title, String.CASE_INSENSITIVE_ORDER)
                        .thenComparing(ref -> ref.itemId().toString()))
                .toList();
    }

    /** With the <strong>current</strong> title, not the one that applied when it was written. */
    private Optional<Ref> describe(String itemType, UUID itemId, UUID reader) {
        if (!access.may(reader, itemType, itemId, AccessLevel.READ)) {
            // Out entirely, not "access denied": even existence is information.
            return Optional.empty();
        }
        var source = sources.get(itemType);
        if (source == null) {
            return Optional.empty();
        }
        // With the number, because the info bar shows it per row.
        // `orElse(null)`: an item created offline does not have one yet.
        return source.titleOf(itemId)
                .map(title -> new Ref(itemType, itemId, title, source.entityKeyOf(itemId).orElse(null)));
    }
}
