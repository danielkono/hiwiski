package de.danielkononov.hiwiski.admin.internal;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.jooq.DSLContext;
import org.jooq.Field;
import org.jooq.JSONB;
import org.jooq.Record;
import org.jooq.Table;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Which tables an archive holds, in which order, and how their values are written.
 *
 * <p><strong>Read from the database's catalog, not from the generated jOOQ
 * classes.</strong> The backup before an update runs while the code is new and the
 * schema old, and a restore fills a staging schema at the archive's version: in both,
 * the generated classes describe a schema that is not the one in front of them.
 */
final class ArchiveTables {

    private static final Logger log = LoggerFactory.getLogger(ArchiveTables.class);

    /** The schema belongs to Flyway; this table is not backed up. */
    static final String FLYWAY_TABLE = "flyway_schema_history";

    /**
     * Tables that can be <strong>derived</strong> and therefore do not belong in the
     * archive.
     *
     * <p>The search index is derived from the domain data: it makes the archive bigger
     * without carrying anything that is not already in it. And it contains a column
     * computed by Postgres that cannot be written back at all —
     * {@code cannot insert a non-DEFAULT value into column "document"}.
     *
     * <p>It is rebuilt after a restore; see {@code SearchIndexer}.
     */
    private static final Set<String> DERIVED_TABLES = Set.of("search_index");

    /**
     * The running server's own bookkeeping, not the family's data: the follow-ups still
     * open (Spring Modulith's event publication log). Restored, a backup brought back
     * follow-ups from the moment it was taken -- already done or long overtaken -- that
     * would be re-run or wait forever; emptied, it would drop the ones running now.
     */
    private static final Set<String> RUNTIME_TABLES = Set.of("event_publication");

    private ArchiveTables() {}

    /**
     * All data tables of {@code schema}, referenced ones before referencing ones.
     *
     * <p>Sorted topologically over the foreign keys in the catalog — a hand-maintained
     * order would be a list that gets forgotten with the next module.
     */
    static List<Table<?>> of(DSLContext db, String schema) {
        List<Table<?>> all = new ArrayList<>(db.meta().filterSchemas(s -> schema.equals(s.getName())).getTables().stream()
                .filter(table -> table.getSchema() != null && schema.equals(table.getSchema().getName()))
                .filter(table -> !FLYWAY_TABLE.equals(table.getName()))
                .filter(table -> !DERIVED_TABLES.contains(table.getName()))
                .filter(table -> !RUNTIME_TABLES.contains(table.getName()))
                .toList());

        List<Table<?>> ordered = new ArrayList<>();
        var remaining = new ArrayList<>(all);
        while (!remaining.isEmpty()) {
            var placed = remaining.stream()
                    .filter(table -> table.getReferences().stream().allMatch(reference -> {
                        String target = reference.getKey().getTable().getName();
                        return target.equals(table.getName())
                                || ordered.stream().anyMatch(done -> done.getName().equals(target));
                    }))
                    .toList();
            if (placed.isEmpty()) {
                // A cycle. Append the rest in any order -- better than not backing up at
                // all, and the cause is in the log.
                log.warn("cyclic foreign keys among {}", remaining.stream().map(Table::getName).toList());
                ordered.addAll(remaining);
                break;
            }
            ordered.addAll(placed);
            remaining.removeAll(placed);
        }
        return ordered;
    }

    /**
     * The columns a row is written with: every one but those Postgres computes itself —
     * {@code GENERATED ALWAYS AS … STORED}, which an {@code INSERT} may not set.
     *
     * <p>A safety net, not a guarantee: jOOQ only knows {@code computed()} if the catalog
     * says so. What can be derived <em>entirely</em> is therefore also listed in
     * {@link #DERIVED_TABLES}.
     */
    static List<Field<?>> columns(Table<?> table) {
        return java.util.Arrays.stream(table.fields())
                .filter(field -> !field.getDataType().computed())
                .toList();
    }

    /**
     * The rows of a table that refers to itself, each after the row it refers to.
     *
     * <p>The table order handles references between tables, not within one: a page
     * refers to its parent page. The dump lists rows as Postgres stores them, and a
     * parent edited after its child was created comes after it -- restored in that
     * order, the child broke the foreign key and the whole restore failed.
     */
    static List<String> selfReferences(Table<?> table) {
        return table.getReferences().stream()
                .filter(reference -> reference.getKey().getTable().getName().equals(table.getName()))
                .flatMap(reference -> reference.getFields().stream().map(Field::getName))
                .toList();
    }

    static List<Map<String, Object>> parentsFirst(Table<?> table, List<Map<String, Object>> rows) {
        List<String> selfReferences = selfReferences(table);
        if (selfReferences.isEmpty() || rows.size() < 2) {
            return rows;
        }
        Map<Object, Map<String, Object>> byId = new LinkedHashMap<>();
        rows.forEach(row -> byId.put(row.get("id"), row));
        List<Map<String, Object>> ordered = new ArrayList<>(rows.size());
        Set<Object> placed = new HashSet<>();
        for (Map<String, Object> row : rows) {
            place(row, byId, selfReferences, placed, ordered, new HashSet<>());
        }
        return ordered;
    }

    private static void place(
            Map<String, Object> row,
            Map<Object, Map<String, Object>> byId,
            List<String> selfReferences,
            Set<Object> placed,
            List<Map<String, Object>> ordered,
            Set<Object> visiting) {
        Object id = row.get("id");
        if (placed.contains(id) || !visiting.add(id)) {
            // Placed already, or a cycle -- which the foreign key would refuse anyway.
            return;
        }
        for (String column : selfReferences) {
            var parent = byId.get(row.get(column));
            if (parent != null) {
                place(parent, byId, selfReferences, placed, ordered, visiting);
            }
        }
        placed.add(id);
        ordered.add(row);
    }

    static Map<String, Object> toMap(Record record, List<Field<?>> columns) {
        Map<String, Object> result = new LinkedHashMap<>();
        for (Field<?> field : columns) {
            result.put(field.getName(), encode(record.get(field)));
        }
        return result;
    }

    private static Object encode(Object value) {
        return switch (value) {
            case null -> null;
            case JSONB jsonb -> Map.of("__jsonb", jsonb.data());
            case UUID uuid -> uuid.toString();
            case OffsetDateTime timestamp -> timestamp.toString();
            case BigDecimal decimal -> decimal.toPlainString();
            case byte[] bytes -> Map.of("__bytes", Base64.getEncoder().encodeToString(bytes));
            case Object[] array -> java.util.Arrays.stream(array).map(ArchiveTables::encode).toList();
            default -> value.toString();
        };
    }

    /**
     * Writes one archived row into {@code table}.
     *
     * <p>A column the archive does not name keeps its default -- a column added since,
     * or one a hand-made archive leaves out; set to {@code null}, it would break its
     * {@code not null}. A name the table does not have is ignored rather than guessed at.
     */
    static void insert(DSLContext db, Table<?> table, List<Field<?>> columns, Map<String, Object> row) {
        Map<Field<?>, Object> values = new LinkedHashMap<>();
        for (Field<?> field : columns) {
            if (!row.containsKey(field.getName())) {
                continue;
            }
            Object raw = row.get(field.getName());
            values.put(field, raw == null ? null : decode(field, raw));
        }
        db.insertInto(table).set(values).execute();
    }

    private static Object decode(Field<?> field, Object raw) {
        if (raw instanceof Map<?, ?> map) {
            if (map.containsKey("__jsonb")) {
                return JSONB.valueOf(String.valueOf(map.get("__jsonb")));
            }
            if (map.containsKey("__bytes")) {
                return Base64.getDecoder().decode(String.valueOf(map.get("__bytes")));
            }
        }
        if (raw instanceof List<?> list) {
            Class<?> component = field.getType().getComponentType();
            Object array = java.lang.reflect.Array.newInstance(component == null ? Object.class : component, list.size());
            for (int i = 0; i < list.size(); i++) {
                java.lang.reflect.Array.set(array, i, field.getDataType().getArrayComponentDataType().convert(list.get(i)));
            }
            return array;
        }
        return field.getDataType().convert(raw);
    }
}
