package de.danielkononov.hiwiski.catalog.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.AISLE;
import static de.danielkononov.hiwiski.db.generated.Tables.PRODUCT;

import de.danielkononov.hiwiski.identity.SetupCompleted;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.jooq.DSLContext;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * The catalog a fresh instance starts with, in the language of the setup wizard.
 *
 * <p>Without it the shopping list would not know for a single row which category it
 * belongs in. Everything beyond it the family teaches the catalog itself, from the
 * shopping list.
 */
@Component
class CatalogSeed {

    /**
     * The built-in categories in their default order — the same as the baseline
     * migration seeds. Repeated here because setup makes sure they exist: a
     * migration runs once, and an instance restored from an empty state or a test that
     * empties the tables would otherwise have none.
     */
    static final List<String> BUILT_IN = List.of(
            "produce", "bakery", "meat_seafood", "deli", "dairy_eggs", "breakfast", "pantry",
            "spices_condiments", "snacks_sweets", "beverages", "frozen", "baby",
            "personal_care", "household", "pet");

    /** The languages a seed exists for; anything else gets English. */
    private static final Set<String> LANGUAGES = Set.of("de", "en");

    private static final String FALLBACK = "en";

    private final DSLContext db;

    CatalogSeed(DSLContext db) {
        this.db = db;
    }

    /**
     * In the setup's transaction. The products a migration seeded before are replaced:
     * on a fresh instance nobody has used them yet.
     */
    @EventListener
    void onSetupCompleted(SetupCompleted setup) {
        Map<String, UUID> aisles = ensureBuiltIns();
        db.deleteFrom(PRODUCT).execute();
        for (Row row : read(language(setup.language()))) {
            db.insertInto(PRODUCT)
                    .set(PRODUCT.ID, UUID.randomUUID())
                    .set(PRODUCT.NAME, row.name())
                    .set(PRODUCT.AISLE_ID, aisles.get(row.aisleKey()))
                    .set(PRODUCT.DEFAULT_UNIT, row.unit())
                    .onConflictDoNothing()
                    .execute();
        }
    }

    /** Key → ID of every built-in category, inserting the missing ones. */
    private Map<String, UUID> ensureBuiltIns() {
        for (int position = 0; position < BUILT_IN.size(); position++) {
            db.insertInto(AISLE)
                    .set(AISLE.ID, UUID.randomUUID())
                    .set(AISLE.KEY, BUILT_IN.get(position))
                    .set(AISLE.POSITION, position)
                    .onConflict(AISLE.KEY)
                    .where(AISLE.KEY.isNotNull())
                    .doNothing()
                    .execute();
        }
        return db.select(AISLE.KEY, AISLE.ID)
                .from(AISLE)
                .where(AISLE.KEY.isNotNull())
                .fetchMap(AISLE.KEY, AISLE.ID);
    }

    static String language(String requested) {
        if (requested == null) {
            return FALLBACK;
        }
        // "de-AT", "de_CH" → "de".
        String language = requested.split("[-_]")[0].toLowerCase(Locale.ROOT);
        return LANGUAGES.contains(language) ? language : FALLBACK;
    }

    record Row(String name, String aisleKey, String unit) {}

    /** {@code name<TAB>category key<TAB>unit}; lines starting with {@code #} are comments. */
    static List<Row> read(String language) {
        String path = "/catalog/products-" + language + ".tsv";
        try (InputStream in = CatalogSeed.class.getResourceAsStream(path)) {
            if (in == null) {
                throw new IllegalStateException("missing " + path);
            }
            return parse(path, new String(in.readAllBytes(), StandardCharsets.UTF_8));
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /**
     * Strict, and naming the line: a line without a tab used to throw an index error
     * inside the setup's transaction -- no family could be set up -- and a key with a
     * typo ("diary_eggs") quietly seeded products without a category.
     */
    static List<Row> parse(String source, String text) {
        var rows = new java.util.ArrayList<Row>();
        var lines = text.lines().toList();
        for (int i = 0; i < lines.size(); i++) {
            String line = lines.get(i).strip();
            if (line.isEmpty() || line.startsWith("#")) {
                continue;
            }
            String[] parts = line.split("\t");
            int number = i + 1;
            if (parts.length < 2 || parts[0].isBlank()) {
                throw new IllegalStateException(source + ":" + number + ": expected name<TAB>category key");
            }
            String key = parts[1].strip();
            if (!BUILT_IN.contains(key)) {
                throw new IllegalStateException(source + ":" + number + ": unknown category key " + key);
            }
            String unit = parts.length > 2 && !parts[2].isBlank() ? parts[2].strip() : null;
            rows.add(new Row(parts[0].strip(), key, unit));
        }
        return rows;
    }
}
