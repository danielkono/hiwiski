package de.danielkononov.hiwiski.platform.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.ENTITY_KEY_COUNTER;

import de.danielkononov.hiwiski.platform.EntityKeys;
import de.danielkononov.hiwiski.platform.InstanceSettings;
import de.danielkononov.hiwiski.platform.KeyedEntityType;
import org.jooq.DSLContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

@Service
class JooqEntityKeys implements EntityKeys {

    private final DSLContext db;
    private final InstanceSettings settings;

    JooqEntityKeys(DSLContext db, InstanceSettings settings) {
        this.db = db;
        this.settings = settings;
    }

    /**
     * {@code MANDATORY} for the same reason as the sequence counter: if the creation is
     * rolled back, the number should be free again.
     *
     * <p>The prefix becomes part of the string when the key is issued -- whoever changes it
     * later only changes what is created afterwards, and a number written down stays
     * valid.
     */
    @Override
    @Transactional(propagation = Propagation.MANDATORY)
    public String next(KeyedEntityType type) {
        long number =
                db.update(ENTITY_KEY_COUNTER)
                        .set(ENTITY_KEY_COUNTER.NEXT, ENTITY_KEY_COUNTER.NEXT.plus(1))
                        .where(ENTITY_KEY_COUNTER.ENTITY_TYPE.eq(type.name()))
                        .returningResult(ENTITY_KEY_COUNTER.NEXT)
                        .fetchSingle()
                        .value1()
                        - 1;
        String prefix = settings.get(type.settingKey(), type.defaultPrefix());
        return prefix + "-" + number;
    }
}
