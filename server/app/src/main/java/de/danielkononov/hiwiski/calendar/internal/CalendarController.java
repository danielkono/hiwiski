package de.danielkononov.hiwiski.calendar.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.CALENDAR;
import static de.danielkononov.hiwiski.db.generated.Tables.CALENDAR_SUBSCRIPTION;

import de.danielkononov.hiwiski.access.Access;
import de.danielkononov.hiwiski.access.AccessLevel;
import de.danielkononov.hiwiski.api.CalendarApi;
import de.danielkononov.hiwiski.api.model.Agenda;
import de.danielkononov.hiwiski.api.model.IcsImportRequest;
import de.danielkononov.hiwiski.api.model.IcsImportResult;
import de.danielkononov.hiwiski.api.model.PreviewEvent;
import de.danielkononov.hiwiski.api.model.RefreshResult;
import de.danielkononov.hiwiski.api.model.SubscriptionPreview;
import de.danielkononov.hiwiski.api.model.SubscriptionPreviewRequest;
import de.danielkononov.hiwiski.identity.CurrentUser;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.util.List;
import java.util.UUID;
import org.jooq.DSLContext;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

/**
 * The calendar's REST endpoints: the "sync now" button, the preview and the import of a
 * file, and the agenda a home screen widget reads ({@link AgendaService}).
 *
 * <p>The server fetches subscriptions at the configured interval anyway — that is the
 * point of a subscription: it lives on the server and not on the device, so that it runs
 * even when no device is online. This endpoint is only for when someone
 * does not want to wait for the next run.
 *
 * <p><strong>A failure while fetching is not a failure of this call.</strong> The
 * subscription stays, the error is noted on it, and the response says what happened. A
 * 500 here would be exactly the state an earlier version failed on — the user saw a server error
 * and not what was wrong with their subscription.
 */
@RestController
class CalendarController implements CalendarApi {

    private final DSLContext db;
    private final SubscriptionService subscriptions;
    private final Access access;
    private final AgendaService agenda;

    CalendarController(DSLContext db, SubscriptionService subscriptions, Access access, AgendaService agenda) {
        this.db = db;
        this.subscriptions = subscriptions;
        this.access = access;
        this.agenda = agenda;
    }

    @Override
    public ResponseEntity<Agenda> getAgenda(List<UUID> calendarIds, Integer days, String timeZone, Integer limit) {
        var principal = CurrentUser.require();
        return ResponseEntity.ok(agenda.agenda(
                principal.memberId(),
                calendarIds == null ? List.of() : calendarIds,
                days == null ? AgendaService.DEFAULT_DAYS : days,
                timeZone,
                limit == null ? AgendaService.DEFAULT_LIMIT : limit,
                java.time.Instant.now()));
    }

    @Override
    public ResponseEntity<RefreshResult> refreshCalendarSubscription(UUID subscriptionId) {
        var principal = CurrentUser.require();

        var row = db.selectFrom(CALENDAR_SUBSCRIPTION)
                .where(CALENDAR_SUBSCRIPTION.ID.eq(subscriptionId))
                .and(CALENDAR_SUBSCRIPTION.DELETED_AT.isNull())
                .fetchOne();
        // 404 and not 403: whoever may not see the subscription should not be able to
        // tell from the response that it exists.
        if (row == null) {
            throw HiwiskiException.notFound("calendar.subscription_not_found", "id", subscriptionId);
        }

        var level = access.levelOf(principal.memberId(), CalendarSyncTypes.CALENDAR_TYPE, row.getCalendarId());
        if (level.isEmpty()) {
            throw HiwiskiException.notFound("calendar.subscription_not_found", "id", subscriptionId);
        }
        // Fetching means writing: the sync creates events and deletes them.
        if (level.get().compareTo(AccessLevel.WRITE) < 0) {
            throw HiwiskiException.forbidden("calendar.subscription_read_only");
        }

        var result = new RefreshResult(subscriptionId, true);
        try {
            result.setImportedCount(subscriptions.refresh(subscriptionId));
        } catch (RuntimeException e) {
            // The note is already on the subscription -- `refresh` sets it in a
            // transaction of its own before rethrowing.
            result.setOk(false);
            result.setError(e instanceof HiwiskiException hiwiski ? hiwiski.code() : "calendar.subscription_failed");
        }

        var after = db.select(CALENDAR_SUBSCRIPTION.LAST_SYNC_AT, CALENDAR_SUBSCRIPTION.IMPORTED_COUNT)
                .from(CALENDAR_SUBSCRIPTION)
                .where(CALENDAR_SUBSCRIPTION.ID.eq(subscriptionId))
                .fetchOne();
        if (after != null) {
            result.setLastSyncAt(after.value1());
            result.setImportedCount(after.value2());
        }
        return ResponseEntity.ok(result);
    }

    @Override
    public ResponseEntity<SubscriptionPreview> previewCalendarSubscription(SubscriptionPreviewRequest request) {
        CurrentUser.require();
        var preview = request.getIcs() != null
                ? subscriptions.previewOf(request.getIcs())
                : subscriptions.preview(requireUrl(request.getUrl()));
        var result = new SubscriptionPreview(
                preview.eventCount(),
                preview.upcoming().stream().map(CalendarController::toPreviewEvent).toList());
        result.setName(preview.name());
        return ResponseEntity.ok(result);
    }

    private static PreviewEvent toPreviewEvent(IcsImporter.Entry entry) {
        var event = new PreviewEvent(entry.title() == null ? "" : entry.title(), "ALL_DAY".equals(entry.timeForm()));
        event.setStartsAt(entry.startsAt());
        event.setStartDate(entry.startDate());
        event.setRecurring(entry.rrule() != null);
        return event;
    }

    @Override
    public ResponseEntity<IcsImportResult> importIcsFile(UUID calendarId, IcsImportRequest request) {
        var principal = CurrentUser.require();
        // A link is fetched once, here -- before any write, so a dead address leaves
        // nothing behind.
        String ics = request.getIcs() != null ? request.getIcs() : subscriptions.fetch(requireUrl(request.getUrl()));

        if (request.getNewCalendar() != null) {
            var wanted = request.getNewCalendar();
            if (wanted.getName() == null || wanted.getName().isBlank()) {
                throw HiwiskiException.invalid("validation.required", "field", "newCalendar.name");
            }
            if (db.fetchExists(CALENDAR, CALENDAR.ID.eq(calendarId))) {
                throw HiwiskiException.invalid("calendar.import_target_exists", "id", calendarId);
            }
            var counts = subscriptions.importIntoNew(
                    calendarId,
                    new SubscriptionService.NewCalendar(
                            wanted.getName().trim(), wanted.getColorToken().getValue(), Boolean.TRUE.equals(wanted.getLocked())),
                    principal.memberId(),
                    ics);
            return ResponseEntity.ok(new IcsImportResult(counts.imported(), counts.updated()));
        }

        var calendar = db.selectFrom(CALENDAR)
                .where(CALENDAR.ID.eq(calendarId))
                .and(CALENDAR.DELETED_AT.isNull())
                .fetchOne();
        var level = calendar == null
                ? java.util.Optional.<AccessLevel>empty()
                : access.levelOf(principal.memberId(), CalendarSyncTypes.CALENDAR_TYPE, calendarId);
        // 404 and not 403 for whoever may not see it.
        if (level.isEmpty()) {
            throw HiwiskiException.notFound("calendar.not_found", "id", calendarId);
        }
        if (level.get().compareTo(AccessLevel.WRITE) < 0) {
            throw HiwiskiException.forbidden("access.denied");
        }
        // A subscribed calendar belongs to its source; an import there would be
        // overwritten or deleted by the next sync.
        if ("EXTERNAL".equals(calendar.getKind())) {
            throw HiwiskiException.invalid("calendar.import_into_subscription");
        }
        var counts = subscriptions.importFile(calendarId, principal.memberId(), ics);
        return ResponseEntity.ok(new IcsImportResult(counts.imported(), counts.updated()));
    }

    /** An address or a file — without either there is nothing to read. */
    private static String requireUrl(String url) {
        if (url == null || url.isBlank()) {
            throw HiwiskiException.invalid("calendar.import_source_missing");
        }
        return url.trim();
    }
}
