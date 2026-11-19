package de.danielkononov.hiwiski.calendar.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.CALENDAR;
import static de.danielkononov.hiwiski.db.generated.Tables.EVENT;

import de.danielkononov.hiwiski.api.model.Agenda;
import de.danielkononov.hiwiski.api.model.AgendaOccurrence;
import de.danielkononov.hiwiski.db.generated.tables.records.EventRecord;
import de.danielkononov.hiwiski.platform.ChangeSequence;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.platform.InstanceSettings;
import de.danielkononov.hiwiski.platform.SettingKey;
import de.danielkononov.hiwiski.recurrence.Recurrence;
import de.danielkononov.hiwiski.sync.ChangeVisibility;
import java.time.DateTimeException;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.jooq.Condition;
import org.jooq.DSLContext;
import org.jooq.impl.DSL;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;

/**
 * The agenda a home screen widget reads: the coming occurrences of the chosen calendars.
 *
 * <p>The app expands its calendar itself, from its own database. The widget asks here
 * because it refreshes while the app is closed; the expansion is the app's, ported
 * ({@link EventOccurrences}, both checked against {@code golden/occurrences.json}).
 *
 * <p><strong>Visibility is part of the query</strong>: an event or a calendar the caller
 * cannot see is never read, so it cannot leak into the answer through a mistake further
 * down.
 */
@Service
class AgendaService {

    static final int DEFAULT_DAYS = 7;
    static final int DEFAULT_LIMIT = 50;

    static final String TIME_ZONE_INVALID = "calendar.time_zone_invalid";

    private static final Logger LOG = LoggerFactory.getLogger(AgendaService.class);

    private static final DateTimeFormatter LOCAL = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm");

    private final DSLContext db;
    private final ChangeVisibility visibility;
    private final ChangeSequence sequence;
    private final InstanceSettings settings;
    private final ObjectMapper mapper;
    private final EventOccurrences occurrences;

    AgendaService(
            DSLContext db,
            ChangeVisibility visibility,
            ChangeSequence sequence,
            InstanceSettings settings,
            ObjectMapper mapper,
            Recurrence recurrence) {
        this.db = db;
        this.visibility = visibility;
        this.sequence = sequence;
        this.settings = settings;
        this.mapper = mapper;
        this.occurrences = new EventOccurrences(recurrence);
    }

    /**
     * @param calendarIds empty: every calendar the member can see
     * @param timeZone the device's zone; {@code null}: the family's
     */
    @Transactional(readOnly = true)
    Agenda agenda(UUID member, List<UUID> calendarIds, int days, String timeZone, int limit, Instant now) {
        ZoneId zone = zone(timeZone);
        // Read before the events: the position may lag behind what is read, never run
        // ahead of it. The widget keeps whichever picture is newer, and one that claimed
        // a change it does not hold would win over the app's picture that has it.
        long position = sequence.current();

        LocalDateTime from = now.atZone(zone).toLocalDateTime().truncatedTo(ChronoUnit.MINUTES);
        LocalDateTime to = from.toLocalDate().plusDays(days).atStartOfDay();

        Map<UUID, String> colors = db.select(CALENDAR.ID, CALENDAR.COLOR_TOKEN)
                .from(CALENDAR)
                .where(CALENDAR.DELETED_AT.isNull())
                .and(visibility.itemVisibleTo(member, CalendarSyncTypes.CALENDAR_TYPE, CALENDAR.ID))
                .fetchMap(CALENDAR.ID, CALENDAR.COLOR_TOKEN);

        record Found(EventRecord event, EventOccurrences.Occurrence occurrence) {}
        List<Found> found = new ArrayList<>();
        Condition chosen = calendarIds.isEmpty() ? DSL.trueCondition() : EVENT.CALENDAR_ID.in(calendarIds);
        for (EventRecord event : db.selectFrom(EVENT)
                .where(EVENT.DELETED_AT.isNull())
                .and(chosen)
                .and(DSL.not(clearlyOutside(from, to, zone)))
                .and(visibility.itemVisibleTo(member, CalendarSyncTypes.EVENT_TYPE, EVENT.ID))
                .fetch()) {
            for (var occurrence : occurrences.expand(times(event), from, to, zone)) {
                found.add(new Found(event, occurrence));
            }
        }
        found.sort(Comparator.comparing(Found::occurrence, EventOccurrences.ORDER)
                .thenComparing(item -> item.event().getTitle()));

        List<AgendaOccurrence> shown = found.stream()
                .limit(limit)
                .map(item -> {
                    var event = item.event();
                    var occurrence = item.occurrence();
                    var row = new AgendaOccurrence(
                            event.getId(),
                            event.getCalendarId(),
                            event.getTitle(),
                            LOCAL.format(occurrence.start()),
                            LOCAL.format(occurrence.end()),
                            occurrence.allDay());
                    row.setLocation(event.getLocation());
                    row.setColorToken(colors.get(event.getCalendarId()));
                    row.setMoved(occurrence.moved());
                    return row;
                })
                .toList();
        return new Agenda(position, zone.getId(), LOCAL.format(from), LOCAL.format(to), shown, found.size() > limit);
    }

    /**
     * Single events that cannot touch the window, left in the database: a subscribed
     * school calendar holds years of them, and the widget asks every quarter of an hour.
     * A day's margin on each side; what is left is expanded exactly.
     */
    private static Condition clearlyOutside(LocalDateTime from, LocalDateTime to, ZoneId zone) {
        var earliest = from.minusDays(1).atZone(zone).toOffsetDateTime();
        var latest = to.plusDays(1).atZone(zone).toOffsetDateTime();
        Condition single = EVENT.RRULE.isNull().or(DSL.trim(EVENT.RRULE).eq(""));
        Condition timed = EVENT.TIME_FORM.eq(EventOccurrences.TIMED)
                .and(DSL.coalesce(EVENT.ENDS_AT, EVENT.STARTS_AT).lt(earliest)
                        .or(EVENT.STARTS_AT.ge(latest)));
        Condition allDay = EVENT.TIME_FORM.eq(EventOccurrences.ALL_DAY)
                .and(DSL.coalesce(EVENT.END_DATE, EVENT.START_DATE).lt(from.toLocalDate().minusDays(1))
                        .or(EVENT.START_DATE.gt(to.toLocalDate().plusDays(1))));
        // `coalesce`: a comparison with a missing time is unknown, and `not` of unknown
        // would drop the row instead of keeping it.
        return DSL.coalesce(DSL.field(single.and(timed.or(allDay))), DSL.inline(false)).isTrue();
    }

    private EventOccurrences.Times times(EventRecord event) {
        return new EventOccurrences.Times(
                event.getTimeForm(),
                event.getStartsAt(),
                event.getEndsAt(),
                event.getStartDate(),
                event.getEndDate(),
                event.getLocalStart(),
                event.getLocalEnd(),
                event.getTimeZone(),
                event.getRrule(),
                exceptions(event));
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> exceptions(EventRecord event) {
        if (event.getExceptions() == null || event.getExceptions().data() == null) {
            return Map.of();
        }
        try {
            Object parsed = mapper.readValue(event.getExceptions().data(), Object.class);
            return parsed instanceof Map<?, ?> map ? (Map<String, Object>) map : Map.of();
        } catch (JacksonException broken) {
            // A broken column must not cost the agenda; the series shows by its rule.
            LOG.warn("Unreadable exceptions on event {}", event.getId());
            return Map.of();
        }
    }

    /** The device's zone; without one the family's, and without that UTC. */
    private ZoneId zone(String requested) {
        if (requested != null && !requested.isBlank()) {
            try {
                return ZoneId.of(requested.trim());
            } catch (DateTimeException unknown) {
                throw HiwiskiException.invalid(TIME_ZONE_INVALID, "timeZone", requested);
            }
        }
        return settings.find(SettingKey.FAMILY_TIMEZONE)
                .flatMap(AgendaService::knownZone)
                .orElse(ZoneOffset.UTC);
    }

    private static Optional<ZoneId> knownZone(String id) {
        try {
            return Optional.of(ZoneId.of(id));
        } catch (DateTimeException unknown) {
            return Optional.empty();
        }
    }
}
