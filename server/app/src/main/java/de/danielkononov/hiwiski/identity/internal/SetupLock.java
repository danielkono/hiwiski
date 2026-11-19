package de.danielkononov.hiwiski.identity.internal;

import org.jooq.DSLContext;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * One at a time for whatever turns a fresh server into a family's: the setup wizard and
 * a restore from the wizard.
 *
 * <p>A lock in the database, held until the transaction that took it ends. Both check
 * "nobody yet" and write afterwards; without it two requests at once both found the
 * server fresh.
 */
@Component
class SetupLock {

    private final DSLContext db;

    SetupLock(DSLContext db) {
        this.db = db;
    }

    /** Waits for whoever holds it, then holds it to the end of the caller's transaction. */
    @Transactional(propagation = Propagation.MANDATORY)
    void hold() {
        db.execute("select pg_advisory_xact_lock(hashtextextended({0}, 0))", "setup");
    }
}
