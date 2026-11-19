package de.danielkononov.hiwiski.calendar.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.CALENDAR;
import static de.danielkononov.hiwiski.db.generated.Tables.CALENDAR_FEED;
import static de.danielkononov.hiwiski.db.generated.Tables.CALENDAR_SUBSCRIPTION;
import static de.danielkononov.hiwiski.db.generated.Tables.EVENT;

import de.danielkononov.hiwiski.platform.KeyedEntityType;
import de.danielkononov.hiwiski.recurrence.Recurrence;
import de.danielkononov.hiwiski.sync.SyncField;
import de.danielkononov.hiwiski.sync.SyncType;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.jooq.Table;
import org.jooq.TableField;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * What {@code calendar} registers with sync.
 *
 * <p>Four beans — that is all the calendar costs the sync module. That is exactly what
 * the inversion is for.
 */
@Configuration
class CalendarSyncTypes {

    private final org.jooq.DSLContext db;
    private final Recurrence recurrence;

    CalendarSyncTypes(org.jooq.DSLContext db, Recurrence recurrence) {
        this.db = db;
        this.recurrence = recurrence;
    }

    /** Our own calendar, but locked like a subscription: filled by an import only. */
    static final String KIND_IMPORTED = "IMPORTED";

    static final String CALENDAR_TYPE = "CALENDAR";
    static final String EVENT_TYPE = "EVENT";
    static final String SUBSCRIPTION_TYPE = "CALENDAR_SUBSCRIPTION";
    static final String FEED_TYPE = "CALENDAR_FEED";

    /**
     * A feed's token, as for a board's address: at least 32 characters that go into an
     * address as they are. The app makes 32 hex characters; a broken or modified client
     * could sync "1", and anyone could then guess the feed's address.
     */
    static final java.util.regex.Pattern FEED_TOKEN = java.util.regex.Pattern.compile("[A-Za-z0-9_-]{32,128}");

    static final String FEED_TOKEN_INVALID = "calendar.feed_token_invalid";

    /**
     * Whether a token looks drawn at random: long enough is not enough, forty times the
     * same letter passed. A random one of this length has far more than eight different
     * characters, whatever alphabet a device draws from.
     */
    static boolean varied(String token) {
        return token.chars().distinct().count() >= 8;
    }

    /** A change a subscribed or locked imported calendar does not take. */
    static final String READ_ONLY = "calendar.read_only";

    /** The kinds whose events belong to their source: only an import or a refresh writes them. */
    private static final java.util.Set<String> LOCKED = java.util.Set.of("EXTERNAL", KIND_IMPORTED);

    /**
     * What the user adds to an event of a locked calendar and keeps over every refresh.
     */
    private static final java.util.Set<String> LOCAL_ADDITIONS = java.util.Set.of("attendees", "tags", "reminderMinutes");

    private boolean locked(UUID calendarId) {
        return calendarId != null
                && db.fetchExists(db.selectOne()
                        .from(CALENDAR)
                        .where(CALENDAR.ID.eq(calendarId))
                        .and(CALENDAR.KIND.in(LOCKED)));
    }

    @Bean
    SyncType calendarSyncType() {
        return new SyncType() {
            @Override
            public String entityType() {
                return CALENDAR_TYPE;
            }

            @Override
            public Table<?> table() {
                return CALENDAR;
            }

            @Override
            public List<SyncField<?>> fields() {
                return List.of(
                        SyncField.text("name", CALENDAR.NAME),
                        SyncField.text("colorToken", CALENDAR.COLOR_TOKEN),
                        // EXTERNAL belongs to a subscription and is read-only; IMPORTED is
                        // ours, but locked the same way -- only an import fills it.
                        SyncField.text("kind", CALENDAR.KIND),
                        SyncField.integer("position", CALENDAR.POSITION),
                        // Apply to every event in the calendar; the app adds them.
                        SyncField.uuidArray("tags", CALENDAR.TAGS),
                        // For every event without a reminder of its own; the app applies
                        // it, like the tags.
                        SyncField.integer("defaultReminderMinutes", CALENDAR.DEFAULT_REMINDER_MINUTES));
            }

            /**
             * The kind is fixed once the calendar exists: turned from EXTERNAL into LOCAL, a
             * subscribed calendar would take edits its next refresh overwrites, and the
             * other way round a writer could lock the owner out of their own calendar.
             */
            @Override
            public Optional<String> refusal(
                    UUID entityId, boolean exists, UUID containerId, Map<String, Object> fields) {
                if (!exists || fields == null || !fields.containsKey("kind")) {
                    return Optional.empty();
                }
                String current = db.select(CALENDAR.KIND).from(CALENDAR).where(CALENDAR.ID.eq(entityId)).fetchOne(CALENDAR.KIND);
                return java.util.Objects.equals(current, fields.get("kind"))
                        ? Optional.empty()
                        : Optional.of(READ_ONLY);
            }

            /**
             * With a calendar go its events and its subscription.
             *
             * <p>Without that the events would still be there on the devices — the
             * {@code on delete cascade} line in the migration only applies to a hard
             * delete, and here the delete is soft.
             */
            @Override
            public List<Ref> alsoDeleted(java.util.UUID entityId) {
                var events = db.select(EVENT.ID)
                        .from(EVENT)
                        .where(EVENT.CALENDAR_ID.eq(entityId))
                        .and(EVENT.DELETED_AT.isNull())
                        .fetch(EVENT.ID)
                        .stream()
                        .map(id -> new Ref(EVENT_TYPE, id));
                var subscriptions = db.select(CALENDAR_SUBSCRIPTION.ID)
                        .from(CALENDAR_SUBSCRIPTION)
                        .where(CALENDAR_SUBSCRIPTION.CALENDAR_ID.eq(entityId))
                        .and(CALENDAR_SUBSCRIPTION.DELETED_AT.isNull())
                        .fetch(CALENDAR_SUBSCRIPTION.ID)
                        .stream()
                        .map(id -> new Ref(SUBSCRIPTION_TYPE, id));
                return java.util.stream.Stream.concat(events, subscriptions).toList();
            }
        };
    }

    @Bean
    SyncType eventSyncType() {
        return new SyncType() {
            @Override
            public String entityType() {
                return EVENT_TYPE;
            }

            @Override
            public Table<?> table() {
                return EVENT;
            }

            @Override
            public List<SyncField<?>> fields() {
                return List.of(
                        SyncField.text("title", EVENT.TITLE),
                        SyncField.text("description", EVENT.DESCRIPTION),
                        SyncField.text("location", EVENT.LOCATION),
                        // Three time forms, three field groups -- each stores something
                        // different.
                        SyncField.text("timeForm", EVENT.TIME_FORM),
                        SyncField.timestamp("startsAt", EVENT.STARTS_AT),
                        SyncField.timestamp("endsAt", EVENT.ENDS_AT),
                        SyncField.date("startDate", EVENT.START_DATE),
                        SyncField.date("endDate", EVENT.END_DATE),
                        SyncField.text("localStart", EVENT.LOCAL_START),
                        SyncField.text("localEnd", EVENT.LOCAL_END),
                        SyncField.text("timeZone", EVENT.TIME_ZONE),
                        SyncField.text("rrule", EVENT.RRULE),
                        // Merged in, not replaced -- exactly what an earlier version forgot here.
                        SyncField.mergedMap("exceptions", EVENT.EXCEPTIONS),
                        SyncField.uuidArray("attendees", EVENT.ATTENDEES),
                        SyncField.uuidArray("tags", EVENT.TAGS),
                        SyncField.integer("reminderMinutes", EVENT.REMINDER_MINUTES),
                        // The calendar is the container and a field too: an event moves
                        // to another calendar through it, checked like every move.
                        SyncField.uuid("calendarId", EVENT.CALENDAR_ID));
            }

            @Override
            public Optional<Container> container() {
                return Optional.of(new Container(CALENDAR_TYPE, EVENT.CALENDAR_ID));
            }

            /**
             * An event is always in a calendar; it can move, but not out of all of them.
             * And what goes into an ICS feed verbatim is checked first (M13).
             *
             * <p>A subscribed or locked imported calendar takes no new events, and of its
             * events only what the user adds -- attendees, tags, a reminder -- changes
             * through sync. The core belongs to the source; only an import or a refresh
             * writes it. The app showed them read-only, but the server
             * took every edit.
             */
            @Override
            public Optional<String> refusal(
                    UUID entityId, boolean exists, UUID containerId, Map<String, Object> fields) {
                if (fields != null && fields.containsKey("calendarId") && containerId == null) {
                    return Optional.of(SyncField.INVALID_FIELD);
                }
                if (!EventFieldCheck.acceptable(fields, recurrence) || !EventFieldCheck.timed(fields, exists)) {
                    return Optional.of(SyncField.INVALID_FIELD);
                }
                UUID current = exists
                        ? db.select(EVENT.CALENDAR_ID).from(EVENT).where(EVENT.ID.eq(entityId)).fetchOne(EVENT.CALENDAR_ID)
                        : null;
                boolean moves = exists && !java.util.Objects.equals(current, containerId);
                if (!exists || moves) {
                    // Into a locked calendar, or out of one.
                    return locked(containerId) || locked(current) ? Optional.of(READ_ONLY) : Optional.empty();
                }
                // The calendar it stays in is no change either.
                boolean core = fields != null
                        && fields.keySet().stream()
                                .anyMatch(name -> !LOCAL_ADDITIONS.contains(name) && !"calendarId".equals(name));
                return core && locked(current) ? Optional.of(READ_ONLY) : Optional.empty();
            }

            @Override
            public Optional<KeyedEntityType> keyType() {
                return Optional.of(KeyedEntityType.EVENT);
            }

            @Override
            public Optional<TableField<?, String>> keyColumn() {
                return Optional.of(EVENT.ENTITY_KEY);
            }
        };
    }

    @Bean
    SyncType calendarSubscriptionSyncType() {
        return new SyncType() {
            @Override
            public String entityType() {
                return SUBSCRIPTION_TYPE;
            }

            @Override
            public Table<?> table() {
                return CALENDAR_SUBSCRIPTION;
            }

            @Override
            public List<SyncField<?>> fields() {
                return List.of(
                        SyncField.text("name", CALENDAR_SUBSCRIPTION.NAME),
                        SyncField.text("url", CALENDAR_SUBSCRIPTION.URL),
                        // The target kind is fixed on creation and locked afterwards:
                        // everything already imported would otherwise be of the wrong type.
                        SyncField.text("targetKind", CALENDAR_SUBSCRIPTION.TARGET_KIND),
                        SyncField.uuid("targetListId", CALENDAR_SUBSCRIPTION.TARGET_LIST_ID),
                        SyncField.text("syncInterval", CALENDAR_SUBSCRIPTION.SYNC_INTERVAL),
                        SyncField.timestamp("lastSyncAt", CALENDAR_SUBSCRIPTION.LAST_SYNC_AT),
                        SyncField.text("lastError", CALENDAR_SUBSCRIPTION.LAST_ERROR),
                        SyncField.integer("importedCount", CALENDAR_SUBSCRIPTION.IMPORTED_COUNT));
            }

            @Override
            public Optional<Container> container() {
                return Optional.of(new Container(CALENDAR_TYPE, CALENDAR_SUBSCRIPTION.CALENDAR_ID));
            }

            /**
             * <strong>A deleted subscription takes its calendar along.</strong>
             *
             * <p>In an earlier version it stayed behind: it then sat empty in the picker for a new
             * event and accepted nothing there, being external.
             * The calendar in turn takes its events along
             * — that is stated on the calendar and need not be repeated here.
             */
            @Override
            public List<Ref> alsoDeleted(java.util.UUID entityId) {
                // Only a calendar of the subscription's owner. One attached to someone
                // else's calendar before that was refused took that whole calendar along
                // when its owner removed the stray subscription.
                var calendarId = db.select(CALENDAR_SUBSCRIPTION.CALENDAR_ID)
                        .from(CALENDAR_SUBSCRIPTION)
                        .join(CALENDAR)
                        .on(CALENDAR.ID.eq(CALENDAR_SUBSCRIPTION.CALENDAR_ID))
                        .where(CALENDAR_SUBSCRIPTION.ID.eq(entityId))
                        .and(CALENDAR.OWNER_ID.eq(CALENDAR_SUBSCRIPTION.OWNER_ID))
                        .fetchOne(CALENDAR_SUBSCRIPTION.CALENDAR_ID);
                return calendarId == null ? List.of() : List.of(new Ref(CALENDAR_TYPE, calendarId));
            }
        };
    }

    /**
     * Several per member.
     *
     * <p>The token travels through sync too, so that the address can be shown on every
     * device of the owner — that is exactly why it is stored in plain text.
     */
    @Bean
    SyncType calendarFeedSyncType() {
        return new SyncType() {
            @Override
            public String entityType() {
                return FEED_TYPE;
            }

            @Override
            public Table<?> table() {
                return CALENDAR_FEED;
            }

            @Override
            public List<SyncField<?>> fields() {
                return List.of(
                        SyncField.text("name", CALENDAR_FEED.NAME),
                        SyncField.uuidArray("calendarIds", CALENDAR_FEED.CALENDAR_IDS),
                        SyncField.text("contentMode", CALENDAR_FEED.CONTENT_MODE),
                        SyncField.text("token", CALENDAR_FEED.TOKEN));
            }

            /** The token guards the feed on its own: long and random, or refused. */
            @Override
            public Optional<String> refusal(
                    UUID entityId, boolean exists, UUID containerId, Map<String, Object> fields) {
                if (fields == null || !fields.containsKey("token")) {
                    return exists ? Optional.empty() : Optional.of(FEED_TOKEN_INVALID);
                }
                Object token = fields.get("token");
                return token != null && FEED_TOKEN.matcher(token.toString()).matches() && varied(token.toString())
                        ? Optional.empty()
                        : Optional.of(FEED_TOKEN_INVALID);
            }

            /** Whoever has the token reads the feed without signing in. */
            @Override
            public java.util.Set<String> secretFields() {
                return java.util.Set.of("token");
            }
        };
    }
}
