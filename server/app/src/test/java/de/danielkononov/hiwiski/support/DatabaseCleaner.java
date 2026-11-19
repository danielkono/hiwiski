package de.danielkononov.hiwiski.support;

import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import org.jooq.DSLContext;
import org.junit.jupiter.api.extension.BeforeEachCallback;
import org.junit.jupiter.api.extension.ExtensionContext;
import org.springframework.test.context.junit.jupiter.SpringExtension;

/**
 * Empties the database before every test.
 *
 * <p>The container runs once per JVM; without this cleanup the second test sees the
 * family of the first, and the order of the tests would become part of the guarantee.
 *
 * <p>{@code truncate ... cascade} over all tables instead of a list of {@code delete}s:
 * it needs no ordering, and a table that a later phase adds is included automatically.
 * Only what belongs to the schema rather than the data is excluded -- the two counters
 * are reset instead.
 */
public class DatabaseCleaner implements BeforeEachCallback {

    private static final Set<String> KEEP =
            Set.of("flyway_schema_history", "change_sequence", "entity_key_counter");

    @Override
    public void beforeEach(ExtensionContext context) {
        clean(SpringExtension.getApplicationContext(context).getBean(DSLContext.class));
    }

    /** Empties the database -- also within a test, to stand for a fresh server. */
    public void clean(DSLContext db) {
        // The previous test's follow-ups -- search index, links, revisions -- run after
        // its commit, in transactions of their own. Truncating under them waited on their
        // locks or let them write stray rows into this test's empty database, depending
        // on timing and test order.
        FollowUps.settle(db);

        List<String> tables =
                db.meta().getTables().stream()
                        .filter(table -> table.getSchema() != null)
                        .filter(table -> "public".equals(table.getSchema().getName()))
                        .map(org.jooq.Named::getName)
                        .filter(name -> !KEEP.contains(name))
                        .distinct()
                        .toList();

        if (!tables.isEmpty()) {
            db.execute(
                    "truncate table "
                            + tables.stream()
                                    .map(name -> "\"" + name + "\"")
                                    .collect(Collectors.joining(", "))
                            + " restart identity cascade");
        }
        db.execute("update change_sequence set seq = 0");
        db.execute("update entity_key_counter set next = 1");
    }
}
