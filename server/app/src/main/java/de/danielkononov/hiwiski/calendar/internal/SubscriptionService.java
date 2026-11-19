package de.danielkononov.hiwiski.calendar.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.CALENDAR;
import static de.danielkononov.hiwiski.db.generated.Tables.CALENDAR_SUBSCRIPTION;
import static de.danielkononov.hiwiski.db.generated.Tables.EVENT;
import static de.danielkononov.hiwiski.db.generated.Tables.MEMBER;

import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.sync.ServerWrites;
import java.time.OffsetDateTime;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.jooq.DSLContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * The sync of an ICS subscription.
 *
 * <p>Two things about it were learned from an earlier version:
 *
 * <ul>
 *   <li><strong>Matching is by UID plus RECURRENCE-ID, never by title.</strong> A title
 *       changes, and then the event would show up twice.
 *   <li><strong>The imported core and local additions are kept apart.</strong> Title and
 *       time belong to the source and are overwritten on every sync; tags, assignment,
 *       reminder and completion belong to the user and survive.
 * </ul>
 */
@Service
class SubscriptionService {

    private static final Logger log = LoggerFactory.getLogger(SubscriptionService.class);

    private final DSLContext db;
    private final IcsFetcher fetcher;
    private final IcsImporter importer;
    private final ServerWrites writes;
    private final SubscriptionStatus status;
    private final TransactionTemplate transaction;
    private final de.danielkononov.hiwiski.access.Access access;

    SubscriptionService(
            DSLContext db,
            IcsFetcher fetcher,
            IcsImporter importer,
            ServerWrites writes,
            SubscriptionStatus status,
            PlatformTransactionManager transactions,
            de.danielkononov.hiwiski.access.Access access) {
        this.access = access;
        this.db = db;
        this.fetcher = fetcher;
        this.importer = importer;
        this.writes = writes;
        this.status = status;
        this.transaction = new TransactionTemplate(transactions);
    }

    /**
     * Fetches and imports.
     *
     * <p>If it fails, the error is noted on the subscription — <strong>in a transaction
     * of its own</strong>. In an earlier version the {@code catch} ran in the same, rolled-back one:
     * instead of a readable state on the subscription, the user got a server error, and
     * the subscription was never even created.
     */
    int refresh(UUID subscriptionId) {
        var subscription = db.selectFrom(CALENDAR_SUBSCRIPTION)
                .where(CALENDAR_SUBSCRIPTION.ID.eq(subscriptionId))
                .and(CALENDAR_SUBSCRIPTION.DELETED_AT.isNull())
                .fetchOne();
        if (subscription == null) {
            throw HiwiskiException.notFound("calendar.subscription_not_found", "id", subscriptionId);
        }

        // The refresh writes in its owner's name -- so only while they may still write the
        // calendar. Otherwise a subscription added to someone else's calendar kept filling
        // and emptying it, night after night, after its owner's share was taken back.
        // And only into the owner's own calendar, while the owner is not disabled: a
        // disabled member writes nothing, through the app or through a refresh in their
        // name, and one attached to someone else's calendar before that was refused
        // stops filling it.
        if (!ownsActiveCalendar(subscription.getOwnerId(), subscription.getCalendarId())
                || !access.may(
                        subscription.getOwnerId(),
                        CalendarSyncTypes.CALENDAR_TYPE,
                        subscription.getCalendarId(),
                        de.danielkononov.hiwiski.access.AccessLevel.WRITE)) {
            status.recordFailure(subscriptionId, subscription.getOwnerId(), READ_ONLY);
            throw HiwiskiException.forbidden(READ_ONLY);
        }

        try {
            String ics = fetcher.fetch(subscription.getUrl());
            // Not one transaction around it: `apply` writes in batches of its own.
            int count = apply(subscription.getId(), subscription.getCalendarId(), subscription.getOwnerId(), ics);
            status.recordSuccess(subscriptionId, subscription.getOwnerId(), count);
            return count;
        } catch (RuntimeException e) {
            // Its own bracket. The note has to arrive precisely because the sync
            // failed.
            status.recordFailure(subscriptionId, subscription.getOwnerId(), message(e));
            throw e;
        }
    }

    private boolean ownsActiveCalendar(UUID owner, UUID calendarId) {
        return db.fetchExists(db.selectOne()
                .from(CALENDAR)
                .join(MEMBER)
                .on(MEMBER.ID.eq(CALENDAR.OWNER_ID))
                .where(CALENDAR.ID.eq(calendarId))
                .and(CALENDAR.OWNER_ID.eq(owner))
                .and(MEMBER.DISABLED_AT.isNull()));
    }

    /**
     * The note on a subscription that may no longer write its calendar: its owner lost
     * write on it, does not own it, or is disabled.
     */
    static final String READ_ONLY = "calendar.subscription_read_only";

    /**
     * Brings a calendar up to its source: the events in batches, then, in a last step
     * of its own, what has gone from the source.
     *
     * <p><strong>Not one transaction for the whole file.</strong> Every write holds the
     * instance's writer lock until its transaction ends, and a calendar of twenty
     * thousand events held it for minutes: no device of the family could save anything
     * meanwhile. A batch that fails leaves the ones before it written -- each event
     * whole, matched by its UID, so the next run takes up where this one stopped -- and
     * nothing deleted: what has gone is only known once every event was seen.
     */
    int apply(UUID subscriptionId, UUID calendarId, UUID owner, String ics) {
        var parsed = importer.read(ics);
        var entries = parsed.entries();
        Set<String> seen = new HashSet<>();
        upsertInBatches(calendarId, owner, entries, seen);
        return transaction.execute(tx -> removeGone(subscriptionId, calendarId, owner, parsed, seen));
    }

    private int removeGone(
            UUID subscriptionId, UUID calendarId, UUID owner, IcsImporter.Parsed parsed, Set<String> seen) {
        var entries = parsed.entries();

        // What has disappeared from the source disappears here too. "What goes along
        // with a delete has to be enumerated".
        //
        // But only what has really gone. An event the file still has but that could not
        // be read is not gone, and deleting it took the tags, attendees and reminder the
        // user had added. Nor is a whole calendar gone because the source briefly
        // answered with an empty or almost empty file.
        if (parsed.anonymous()) {
            log.info("subscription {}: an unreadable event without UID, nothing deleted", subscriptionId);
            return entries.size();
        }
        var gone = db.select(EVENT.ID, EVENT.SOURCE_UID, EVENT.SOURCE_RECURRENCE_ID)
                .from(EVENT)
                .where(EVENT.CALENDAR_ID.eq(calendarId))
                .and(EVENT.SOURCE_UID.isNotNull())
                .and(EVENT.DELETED_AT.isNull())
                .fetch();
        int existing = gone.size();
        gone.removeIf(row -> seen.contains(key(row.value2(), row.value3()))
                || parsed.unreadable().contains(row.value2()));
        if (looksLikeAnOutage(existing, gone.size(), entries.size())) {
            log.info("subscription {}: {} of {} events would vanish, nothing deleted",
                    subscriptionId, gone.size(), existing);
            return entries.size();
        }
        for (var row : gone) {
            // Only what the subscription's owner may delete: not an event someone gave a
            // share of its own that leaves them out.
            if (mayWrite(owner, row.value1())) {
                writes.delete(CalendarSyncTypes.EVENT_TYPE, row.value1(), owner);
            }
        }

        return entries.size();
    }

    /** From this many events on, losing nearly all of them at once is not believed. */
    static final int OUTAGE_MINIMUM = 10;

    /**
     * Whether a refresh that would delete [vanishing] of [existing] events looks like a
     * broken source rather than a changed one: an empty file, or nine in ten gone.
     */
    static boolean looksLikeAnOutage(int existing, int vanishing, int read) {
        if (vanishing == 0) {
            return false;
        }
        return read == 0 || (existing >= OUTAGE_MINIMUM && vanishing * 10 > existing * 9);
    }

    /** How a one-off import went: new events and ones that were there already. */
    record ImportCounts(int imported, int updated) {}

    /**
     * A one-off import of a file into one of our calendars.
     *
     * <p>Unlike a subscription nothing is deleted — the calendar is ours, and an event
     * missing from the file is not gone. The same matching by UID, so a second import of
     * the same file updates instead of doubling.
     */
    ImportCounts importFile(UUID calendarId, UUID actor, String ics) {
        return upsertInBatches(calendarId, actor, importer.parse(ics), new HashSet<>());
    }

    /** How many events one transaction writes, and so how long the others wait at most. */
    static final int BATCH = 50;

    /**
     * {@link #upsert} batch by batch, each in a transaction of its own (see
     * {@link #apply}): between two batches every other writer gets its turn.
     */
    private ImportCounts upsertInBatches(
            UUID calendarId, UUID owner, java.util.List<IcsImporter.Entry> entries, Set<String> seen) {
        int created = 0;
        int updated = 0;
        for (int from = 0; from < entries.size(); from += BATCH) {
            var batch = entries.subList(from, Math.min(entries.size(), from + BATCH));
            ImportCounts counts = transaction.execute(tx -> upsert(calendarId, owner, batch, seen));
            created += counts.imported();
            updated += counts.updated();
        }
        return new ImportCounts(created, updated);
    }

    /** A calendar the import creates — {@code locked}: read only, like a subscription's. */
    record NewCalendar(String name, String colorToken, boolean locked) {}

    /**
     * The import into a calendar it creates first. The file is read before anything is
     * written, so one that cannot be read leaves no empty calendar behind; the events
     * then follow in batches, like every import.
     */
    ImportCounts importIntoNew(UUID calendarId, NewCalendar calendar, UUID actor, String ics) {
        var entries = importer.parse(ics);
        Map<String, Object> fields = new LinkedHashMap<>();
        fields.put("name", calendar.name());
        fields.put("colorToken", calendar.colorToken());
        // IMPORTED: our own, but locked like a subscription -- the events stay as the file
        // had them, and only a further import changes them.
        fields.put("kind", calendar.locked() ? CalendarSyncTypes.KIND_IMPORTED : "LOCAL");
        fields.put("position", 0);
        transaction.executeWithoutResult(
                tx -> writes.upsert(CalendarSyncTypes.CALENDAR_TYPE, calendarId, null, null, fields, actor));
        return upsertInBatches(calendarId, actor, entries, new HashSet<>());
    }

    /** The file behind an address — fetched once, with every guard of a subscription. */
    String fetch(String url) {
        return fetcher.fetch(url);
    }

    /** What a file holds, without storing anything — for the preview before subscribing. */
    record Preview(String name, int eventCount, java.util.List<IcsImporter.Entry> upcoming) {}

    /** How many of the next events the preview lists — enough for an overview. */
    private static final int PREVIEW_EVENTS = 20;

    Preview preview(String url) {
        return previewOf(fetcher.fetch(url));
    }

    Preview previewOf(String ics) {
        var entries = importer.parse(ics);
        java.time.LocalDate today = java.time.LocalDate.now();
        var upcoming = entries.stream()
                .filter(entry -> entry.rrule() != null || !firstDay(entry).isBefore(today))
                .sorted(java.util.Comparator.comparing(SubscriptionService::firstDay))
                .limit(PREVIEW_EVENTS)
                .toList();
        return new Preview(importer.calendarName(ics).orElse(null), entries.size(), upcoming);
    }

    private static java.time.LocalDate firstDay(IcsImporter.Entry entry) {
        if (entry.startDate() != null) {
            return entry.startDate();
        }
        if (entry.startsAt() != null) {
            return entry.startsAt().toLocalDate();
        }
        if (entry.localStart() != null) {
            return java.time.LocalDateTime.parse(entry.localStart()).toLocalDate();
        }
        return java.time.LocalDate.MAX;
    }

    /**
     * Writes the entries into the calendar, matched by UID plus RECURRENCE-ID.
     *
     * <p>One import per calendar at a time, until the batch's transaction ends: the scheduled
     * run, "sync now" and the first fetch all check for a UID first and insert after,
     * and two of them at once inserted the same event twice.
     */
    private ImportCounts upsert(UUID calendarId, UUID owner, java.util.List<IcsImporter.Entry> entries, Set<String> seen) {
        db.execute("select pg_advisory_xact_lock(hashtextextended({0}, 0))", "calendar-import:" + calendarId);
        int created = 0;
        int updated = 0;
        for (IcsImporter.Entry entry : entries) {
            seen.add(key(entry.uid(), entry.recurrenceId()));

            UUID eventId = db.select(EVENT.ID)
                    .from(EVENT)
                    .where(EVENT.CALENDAR_ID.eq(calendarId))
                    .and(EVENT.SOURCE_UID.eq(entry.uid()))
                    .and(entry.recurrenceId() == null
                            ? EVENT.SOURCE_RECURRENCE_ID.isNull()
                            : EVENT.SOURCE_RECURRENCE_ID.eq(entry.recurrenceId()))
                    .fetchOne(EVENT.ID);

            boolean isNew = eventId == null;
            if (isNew) {
                eventId = UUID.randomUUID();
            } else if (!mayWrite(owner, eventId)) {
                // The UID is taken by an event the importer may not write -- one with a share
                // of its own that leaves them out. It stays as it is: matching by UID alone
                // let anyone who may write the calendar overwrite it.
                continue;
            }

            // Only the core. What the user added -- assignment, reminder -- is not in
            // this map and therefore survives every sync.
            Map<String, Object> fields = new LinkedHashMap<>();
            fields.put("title", entry.title());
            fields.put("description", entry.description());
            fields.put("location", entry.location());
            fields.put("timeForm", entry.timeForm());
            fields.put("startsAt", entry.startsAt() == null ? null : entry.startsAt().toString());
            fields.put("endsAt", entry.endsAt() == null ? null : entry.endsAt().toString());
            fields.put("startDate", entry.startDate() == null ? null : entry.startDate().toString());
            fields.put("endDate", entry.endDate() == null ? null : entry.endDate().toString());
            fields.put("localStart", entry.localStart());
            fields.put("localEnd", entry.localEnd());
            fields.put("timeZone", entry.timeZone());
            fields.put("rrule", entry.rrule());
            if (!entry.exceptions().isEmpty()) {
                // Merged in, like every exception: a day the source no
                // longer excludes stays excluded until the event is imported anew.
                fields.put("exceptions", entry.exceptions());
            }

            writes.upsert(
                    CalendarSyncTypes.EVENT_TYPE,
                    eventId,
                    CalendarSyncTypes.CALENDAR_TYPE,
                    calendarId,
                    fields,
                    owner);

            if (isNew) {
                db.update(EVENT)
                        .set(EVENT.SOURCE_UID, entry.uid())
                        .set(EVENT.SOURCE_RECURRENCE_ID, entry.recurrenceId())
                        .where(EVENT.ID.eq(eventId))
                        .execute();
                created++;
            } else {
                updated++;
            }
        }
        return new ImportCounts(created, updated);
    }

    private boolean mayWrite(UUID actor, UUID eventId) {
        return access.may(actor, CalendarSyncTypes.EVENT_TYPE, eventId, de.danielkononov.hiwiski.access.AccessLevel.WRITE);
    }

    private static String message(RuntimeException e) {
        return e instanceof HiwiskiException hiwiski ? hiwiski.code() : "calendar.subscription_failed";
    }

    private static String key(String uid, String recurrenceId) {
        return uid + "\u0000" + (recurrenceId == null ? "" : recurrenceId);
    }

    /**
     * The server fetches subscriptions regularly, <strong>even when no device is
     * online</strong>. That is exactly the difference from an import on
     * the phone.
     */
    @Scheduled(cron = "0 15 * * * *")
    public void refreshDue() {
        var due = db.select(CALENDAR_SUBSCRIPTION.ID, CALENDAR_SUBSCRIPTION.SYNC_INTERVAL,
                        CALENDAR_SUBSCRIPTION.LAST_SYNC_AT)
                .from(CALENDAR_SUBSCRIPTION)
                .where(CALENDAR_SUBSCRIPTION.DELETED_AT.isNull())
                .fetch();

        for (var row : due) {
            if (!isDue(row.value2(), row.value3(), OffsetDateTime.now())) {
                continue;
            }
            try {
                refresh(row.value1());
            } catch (RuntimeException e) {
                // The error is noted on the subscription; the job carries on. A
                // subscription that aborted the whole run would let the others go stale.
                log.info("subscription {} failed to refresh: {}", row.value1(), e.getMessage());
            }
        }
    }

    /**
     * How much earlier than its interval a subscription counts as due. {@code
     * lastSyncAt} is written when a fetch has finished, a few seconds after the run
     * that started it; the next run, one interval later, found it just short of due
     * and skipped it -- hourly ones refreshed every two hours, daily ones every two days.
     */
    static final java.time.Duration DUE_TOLERANCE = java.time.Duration.ofMinutes(5);

    static boolean isDue(String interval, OffsetDateTime lastSync, OffsetDateTime now) {
        if (lastSync == null) {
            return true;
        }
        var age = java.time.Duration.between(lastSync, now).plus(DUE_TOLERANCE);
        var every = switch (interval) {
            case "HOURLY" -> java.time.Duration.ofHours(1);
            case "WEEKLY" -> java.time.Duration.ofDays(7);
            default -> java.time.Duration.ofDays(1);
        };
        return age.compareTo(every) >= 0;
    }
}
