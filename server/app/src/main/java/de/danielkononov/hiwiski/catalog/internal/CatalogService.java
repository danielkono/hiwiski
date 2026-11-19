package de.danielkononov.hiwiski.catalog.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.AISLE;
import static de.danielkononov.hiwiski.db.generated.Tables.PRODUCT;

import de.danielkononov.hiwiski.api.model.Aisle;
import de.danielkononov.hiwiski.api.model.Product;
import de.danielkononov.hiwiski.db.generated.tables.records.AisleRecord;
import de.danielkononov.hiwiski.db.generated.tables.records.ProductRecord;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.UUID;
import org.jooq.DSLContext;
import org.jooq.impl.DSL;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Products and categories (catalog).
 *
 * <p>Built-in categories carry a key and are shown in the app's language; the family's
 * own carry a name. Built-in ones are never deleted, only hidden — a product may point
 * at them, and an older app knows them by key.
 */
@Service
class CatalogService {

    /** Enough for a suggestion list; beyond that you keep typing. */
    private static final int LIMIT = 50;

    private final DSLContext db;

    CatalogService(DSLContext db) {
        this.db = db;
    }

    /**
     * With a term, a suggestion list; without one, <strong>the whole catalog</strong>:
     * the app keeps it for the shopping list's categories, and those have to be right
     * offline. It used to stop at 2000 without a word -- every product past that name
     * in the alphabet lost its category on the devices. By name: a usage count was
     * sorted by but never counted.
     */
    List<Product> products(String query) {
        boolean all = query == null || query.isBlank();
        var select = db.selectFrom(PRODUCT)
                .where(all ? DSL.trueCondition() : PRODUCT.NAME.containsIgnoreCase(query.trim()))
                .orderBy(PRODUCT.NAME.asc());
        return (all ? select.fetch() : select.limit(LIMIT).fetch()).map(CatalogService::toProduct);
    }

    /**
     * The product with exactly this name goes into this category; if there is none, it is
     * created.
     *
     * <p>Exactly and not the longest contained name, as the shopping list finds it:
     * moving "Hokkaido-Kürbis" must not move "Kürbis" along with it.
     */
    @Transactional
    Product assign(String name, UUID aisleId) {
        String trimmed = name == null ? "" : name.trim();
        if (trimmed.isEmpty()) {
            throw HiwiskiException.invalid("catalog.product_name_required");
        }
        if (aisleId != null) {
            requireAisle(aisleId);
        }
        // The row as written, from the upsert itself: read again with a name lowercased
        // by Java, a name the JVM and the database fold differently ("İzmir") found
        // nothing, and the request failed with a 500.
        return toProduct(db.insertInto(PRODUCT)
                .set(PRODUCT.ID, UUID.randomUUID())
                .set(PRODUCT.NAME, trimmed)
                .set(PRODUCT.AISLE_ID, aisleId)
                .onConflict(DSL.lower(PRODUCT.NAME))
                .doUpdate()
                .set(PRODUCT.AISLE_ID, aisleId)
                .returning()
                .fetchSingle());
    }

    List<Aisle> aisles() {
        return db.selectFrom(AISLE)
                .orderBy(AISLE.POSITION, AISLE.CREATED_AT)
                .fetch()
                .map(CatalogService::toAisle);
    }

    /** An own category, at the end of the order. */
    @Transactional
    Aisle createAisle(String name) {
        String trimmed = requireName(name);
        requireNameFree(trimmed, null);
        Integer last = db.select(DSL.max(AISLE.POSITION)).from(AISLE).fetchOne(0, Integer.class);
        var row = db.newRecord(AISLE);
        row.setId(UUID.randomUUID());
        row.setName(trimmed);
        row.setPosition(last == null ? 0 : last + 1);
        row.setHidden(false);
        storeNamed(row);
        return toAisle(row);
    }

    /**
     * Stores a category with a name, and answers a name taken meanwhile -- two devices
     * creating "Asia shop" at once both passed the check -- with the documented 409
     * instead of an unmapped constraint violation and a 500.
     */
    private static void storeNamed(AisleRecord row) {
        try {
            row.store();
        } catch (org.springframework.dao.DuplicateKeyException
                | org.jooq.exception.IntegrityConstraintViolationException e) {
            throw HiwiskiException.conflict("catalog.aisle_name_taken", "name", row.getName());
        }
    }

    @Transactional
    Aisle updateAisle(UUID id, String name, Boolean hidden) {
        AisleRecord row = requireAisle(id);
        if (name != null) {
            if (row.getKey() != null) {
                throw HiwiskiException.invalid("catalog.aisle_builtin", "aisleId", id.toString());
            }
            String trimmed = requireName(name);
            requireNameFree(trimmed, id);
            row.setName(trimmed);
        }
        if (hidden != null) {
            row.setHidden(hidden);
        }
        storeNamed(row);
        return toAisle(row);
    }

    /** Its products lose their category — the foreign key sets them to null. */
    @Transactional
    void deleteAisle(UUID id) {
        AisleRecord row = requireAisle(id);
        if (row.getKey() != null) {
            throw HiwiskiException.invalid("catalog.aisle_builtin", "aisleId", id.toString());
        }
        row.delete();
    }

    /**
     * The named categories first, in the given order; the rest after them in their
     * previous order. One added on another device meanwhile is not lost.
     */
    @Transactional
    List<Aisle> reorder(List<UUID> ids) {
        List<AisleRecord> rows = db.selectFrom(AISLE)
                .orderBy(AISLE.POSITION, AISLE.CREATED_AT)
                .forUpdate()
                .fetch();
        var byId = new java.util.HashMap<UUID, AisleRecord>();
        rows.forEach(row -> byId.put(row.getId(), row));
        var order = new LinkedHashSet<UUID>();
        for (UUID id : ids == null ? List.<UUID>of() : ids) {
            if (byId.containsKey(id)) {
                order.add(id);
            }
        }
        rows.forEach(row -> order.add(row.getId()));
        int position = 0;
        var result = new ArrayList<AisleRecord>();
        for (UUID id : order) {
            AisleRecord row = byId.get(id);
            if (row.getPosition() != position) {
                row.setPosition(position);
                row.store();
            }
            result.add(row);
            position++;
        }
        return result.stream().map(CatalogService::toAisle).toList();
    }

    private AisleRecord requireAisle(UUID id) {
        AisleRecord row = db.selectFrom(AISLE).where(AISLE.ID.eq(id)).fetchOne();
        if (row == null) {
            throw HiwiskiException.notFound("catalog.aisle_not_found", "aisleId", id.toString());
        }
        return row;
    }

    private static String requireName(String name) {
        String trimmed = name == null ? "" : name.trim();
        if (trimmed.isEmpty()) {
            throw HiwiskiException.invalid("catalog.aisle_name_required");
        }
        return trimmed;
    }

    /** Two "Asia shop" in the picker could not be told apart. */
    private void requireNameFree(String name, UUID except) {
        boolean taken = db.fetchExists(db.selectOne()
                .from(AISLE)
                // Lowercased by the database on both sides, as the unique index does.
                .where(DSL.lower(AISLE.NAME).eq(DSL.lower(DSL.val(name))))
                .and(except == null ? DSL.trueCondition() : AISLE.ID.ne(except)));
        if (taken) {
            throw HiwiskiException.conflict("catalog.aisle_name_taken", "name", name);
        }
    }

    private static Product toProduct(ProductRecord row) {
        var product = new Product(row.getId(), row.getName());
        product.setAisleId(row.getAisleId());
        product.setDefaultUnit(row.getDefaultUnit());
        product.setUsageCount(row.getUsageCount());
        return product;
    }

    private static Aisle toAisle(AisleRecord row) {
        var aisle = new Aisle(row.getId(), row.getPosition(), row.getHidden());
        aisle.setKey(row.getKey());
        aisle.setName(row.getName());
        return aisle;
    }
}
