package de.danielkononov.hiwiski.calendar.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.EVENT;

import de.danielkononov.hiwiski.link.LinkSource;
import java.util.Optional;
import java.util.UUID;
import org.jooq.DSLContext;
import org.springframework.stereotype.Component;

/**
 * What {@code calendar} registers with {@code link}.
 *
 * <p>Without this registration {@code #EVT-01} would not be a reference: an event's note
 * would not be parsed, and an event could not be reached as a target either — although
 * the app shows reference chips and the "References" row in the info bar for it.
 */
@Component
class CalendarLinkSource implements LinkSource {

    private final DSLContext db;

    CalendarLinkSource(DSLContext db) {
        this.db = db;
    }

    @Override
    public String itemType() {
        return CalendarSyncTypes.EVENT_TYPE;
    }

    @Override
    public String textOf(UUID itemId) {
        return db.select(EVENT.DESCRIPTION).from(EVENT).where(EVENT.ID.eq(itemId)).fetchOne(EVENT.DESCRIPTION);
    }

    @Override
    public Optional<String> titleOf(UUID itemId) {
        return Optional.ofNullable(db.select(EVENT.TITLE)
                .from(EVENT)
                .where(EVENT.ID.eq(itemId))
                .and(EVENT.DELETED_AT.isNull())
                .fetchOne(EVENT.TITLE));
    }

    @Override
    public Optional<String> entityKeyOf(UUID itemId) {
        // Imported events have none: a holiday calendar would use up five hundred
        // numbers for something nobody cites.
        return Optional.ofNullable(
                db.select(EVENT.ENTITY_KEY).from(EVENT).where(EVENT.ID.eq(itemId)).fetchOne(EVENT.ENTITY_KEY));
    }

    @Override
    public Optional<UUID> byEntityKey(String entityKey) {
        return Optional.ofNullable(db.select(EVENT.ID)
                .from(EVENT)
                .where(EVENT.ENTITY_KEY.eq(entityKey))
                .and(EVENT.DELETED_AT.isNull())
                .fetchOne(EVENT.ID));
    }
}
