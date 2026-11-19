package de.danielkononov.hiwiski.calendar.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.CALENDAR;
import static de.danielkononov.hiwiski.db.generated.Tables.EVENT;

import de.danielkononov.hiwiski.search.Searchable;
import java.util.Optional;
import java.util.UUID;
import java.util.function.BiPredicate;
import org.jooq.DSLContext;
import org.springframework.stereotype.Component;

/** What {@code calendar} registers with {@code search}. */
@Component
class EventSearchable implements Searchable {

    private final DSLContext db;

    EventSearchable(DSLContext db) {
        this.db = db;
    }

    @Override
    public String itemType() {
        return CalendarSyncTypes.EVENT_TYPE;
    }

    @Override
    public Optional<Entry> entryOf(UUID itemId) {
        var row = db.select(
                        EVENT.OWNER_ID,
                        EVENT.TITLE,
                        EVENT.DESCRIPTION,
                        EVENT.LOCATION,
                        EVENT.ENTITY_KEY,
                        CALENDAR.NAME)
                .from(EVENT)
                .leftJoin(CALENDAR)
                .on(CALENDAR.ID.eq(EVENT.CALENDAR_ID))
                .where(EVENT.ID.eq(itemId))
                .and(EVENT.DELETED_AT.isNull())
                .fetchOne();

        if (row == null) {
            return Optional.empty();
        }

        // Location and description both belong in the body: "Gartenstrasse" should find
        // the event even if it is only in the location.
        String body = java.util.stream.Stream.of(row.value3(), row.value4())
                .filter(value -> value != null && !value.isBlank())
                .reduce((a, b) -> a + "\n" + b)
                .orElse("");

        return Optional.of(new Entry(row.value1(), row.value2(), body, row.value5(), row.value6()));
    }

    /** The calendar's name — if the reader may see the calendar, not only the event. */
    @Override
    public String contextFor(UUID itemId, String indexed, BiPredicate<String, UUID> visible) {
        var row = db.select(CALENDAR.ID, CALENDAR.NAME)
                .from(EVENT)
                .join(CALENDAR)
                .on(CALENDAR.ID.eq(EVENT.CALENDAR_ID))
                .where(EVENT.ID.eq(itemId))
                .fetchOne();
        return row != null && visible.test(CalendarSyncTypes.CALENDAR_TYPE, row.value1()) ? row.value2() : null;
    }
}
