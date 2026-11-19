package de.danielkononov.hiwiski.platform.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.CHANGE_SEQUENCE;

import de.danielkononov.hiwiski.platform.ChangeSequence;
import org.jooq.DSLContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

@Service
class JooqChangeSequence implements ChangeSequence {

    private final DSLContext db;

    JooqChangeSequence(DSLContext db) {
        this.db = db;
    }

    /**
     * {@code MANDATORY}: the number may only be drawn inside a running transaction. The
     * row lock holds until its commit, and the promise that number order and commit
     * order match rests on exactly that. Drawn in a transaction of its own, it would be
     * visible again right away and the promise would be broken.
     */
    @Override
    @Transactional(propagation = Propagation.MANDATORY)
    public long next() {
        return db.update(CHANGE_SEQUENCE)
                .set(CHANGE_SEQUENCE.SEQ, CHANGE_SEQUENCE.SEQ.plus(1))
                .returningResult(CHANGE_SEQUENCE.SEQ)
                .fetchSingle()
                .value1();
    }

    @Override
    @Transactional(readOnly = true)
    public long current() {
        return db.select(CHANGE_SEQUENCE.SEQ).from(CHANGE_SEQUENCE).fetchSingle().value1();
    }
}
