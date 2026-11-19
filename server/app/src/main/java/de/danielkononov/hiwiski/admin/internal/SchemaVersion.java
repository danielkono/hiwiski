package de.danielkononov.hiwiski.admin.internal;

import org.flywaydb.core.api.MigrationVersion;
import org.jooq.DSLContext;
import org.jooq.impl.DSL;

/** The version Flyway last applied to a schema -- what an archive's data is shaped like. */
final class SchemaVersion {

    private SchemaVersion() {}

    /**
     * By the order applied, not by the largest text: as text, {@code 9} is larger than
     * {@code 36}.
     */
    static String of(DSLContext db, String schema) {
        String version = db.select(DSL.field(DSL.name("version"), String.class))
                .from(DSL.table(DSL.name(schema, ArchiveTables.FLYWAY_TABLE)))
                .where(DSL.field(DSL.name("success"), Boolean.class).isTrue())
                .and(DSL.field(DSL.name("version")).isNotNull())
                .orderBy(DSL.field(DSL.name("installed_rank")).desc())
                .limit(1)
                .fetchOne(0, String.class);
        if (version == null) {
            throw new IllegalStateException("no migration applied to schema " + schema);
        }
        return version;
    }

    /** Whether {@code archive} is newer than {@code server} -- {@code 036} and {@code 36} are the same. */
    static boolean newer(String archive, String server) {
        return MigrationVersion.fromVersion(archive).compareTo(MigrationVersion.fromVersion(server)) > 0;
    }
}
