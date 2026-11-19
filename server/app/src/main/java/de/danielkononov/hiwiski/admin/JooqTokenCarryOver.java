package de.danielkononov.hiwiski.admin;

import java.util.HashMap;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import org.jooq.DSLContext;
import org.jooq.Field;
import org.jooq.Table;

/**
 * A {@link RestoreCarryOver} for one token column: every row that still exists keeps the
 * token it has now, not the one the archive has.
 */
public class JooqTokenCarryOver implements RestoreCarryOver {

    private record Tokens(Map<UUID, String> byId) implements Snapshot {}

    private final DSLContext db;
    private final Table<?> table;
    private final Field<UUID> id;
    private final Field<String> token;

    public JooqTokenCarryOver(DSLContext db, Table<?> table, Field<UUID> id, Field<String> token) {
        this.db = db;
        this.table = table;
        this.id = id;
        this.token = token;
    }

    @Override
    public Snapshot capture() {
        Map<UUID, String> tokens = new HashMap<>();
        db.select(id, token).from(table).forEach(row -> tokens.put(row.value1(), row.value2()));
        return new Tokens(tokens);
    }

    /**
     * Row by row, only where the token differs. Tokens are random and never move from
     * one row to another, so the table's unique index on them is not in the way.
     */
    @Override
    public void carryOver(Snapshot snapshot) {
        Map<UUID, String> current = ((Tokens) snapshot).byId();
        for (var row : db.select(id, token).from(table).fetch()) {
            UUID rowId = row.value1();
            if (current.containsKey(rowId) && !Objects.equals(row.value2(), current.get(rowId))) {
                db.update(table).set(token, current.get(rowId)).where(id.eq(rowId)).execute();
            }
        }
    }
}
