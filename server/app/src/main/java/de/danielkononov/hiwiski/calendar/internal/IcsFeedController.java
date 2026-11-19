package de.danielkononov.hiwiski.calendar.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.CALENDAR;
import static de.danielkononov.hiwiski.db.generated.Tables.CALENDAR_FEED;
import static de.danielkononov.hiwiski.db.generated.Tables.EVENT;

import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.time.OffsetDateTime;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;
import org.jooq.DSLContext;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

/**
 * The ICS export at its own address.
 *
 * <p>"Share a calendar as an address, to subscribe to it e.g. in the phone's calendar
 * or at grandma's. <strong>Read-only, revocable at any time.</strong>"
 *
 * <p>Without authentication: a foreign calendar program cannot send a device token. The
 * token sits in plain text in the address instead, can only read, and only what was
 * selected.
 *
 * <p>Outside the spec, like the SSE stream: the body is {@code text/calendar}, and a
 * generated Dart client for it would be a signature nobody calls — the file is fetched
 * by a foreign program, not by this app.
 */
@RestController
class IcsFeedController {

    private final DSLContext db;
    private final IcsWriter writer;
    private final de.danielkononov.hiwiski.sync.ChangeVisibility visibility;

    IcsFeedController(DSLContext db, IcsWriter writer, de.danielkononov.hiwiski.sync.ChangeVisibility visibility) {
        this.db = db;
        this.writer = writer;
        this.visibility = visibility;
    }

    @GetMapping(value = "/ics/{token}.ics", produces = "text/calendar;charset=UTF-8")
    @Transactional
    ResponseEntity<String> feed(@PathVariable String token) {
        if (!CalendarSyncTypes.FEED_TOKEN.matcher(token).matches()) {
            // A weak token from before the server checked it opens nothing; the owner
            // makes a new link.
            throw HiwiskiException.notFound("calendar.feed_not_found");
        }
        // Like the board's address: the link can do nothing its owner cannot, and a member
        // the administrator disabled keeps no feed running on someone's phone.
        var feed = db.select(CALENDAR_FEED.fields())
                .from(CALENDAR_FEED)
                .join(de.danielkononov.hiwiski.db.generated.Tables.MEMBER)
                .on(de.danielkononov.hiwiski.db.generated.Tables.MEMBER.ID.eq(CALENDAR_FEED.OWNER_ID))
                .where(CALENDAR_FEED.TOKEN.eq(token))
                .and(CALENDAR_FEED.DELETED_AT.isNull())
                .and(de.danielkononov.hiwiski.db.generated.Tables.MEMBER.DISABLED_AT.isNull())
                .fetchOneInto(CALENDAR_FEED);
        if (feed == null) {
            // A revoked link looks like a made-up one.
            throw HiwiskiException.notFound("calendar.feed_not_found");
        }

        db.update(CALENDAR_FEED)
                .set(CALENDAR_FEED.LAST_ACCESS_AT, OffsetDateTime.now())
                .where(CALENDAR_FEED.ID.eq(feed.getId()))
                .execute();

        List<UUID> calendars = Arrays.asList(feed.getCalendarIds());
        boolean busyOnly = "BUSY".equals(feed.getContentMode());

        var entries = calendars.isEmpty()
                ? List.<IcsWriter.Entry>of()
                : db.select(EVENT.fields())
                        .from(EVENT)
                        .join(CALENDAR)
                        .on(CALENDAR.ID.eq(EVENT.CALENDAR_ID))
                        .where(EVENT.CALENDAR_ID.in(calendars))
                        .and(EVENT.DELETED_AT.isNull())
                        .and(CALENDAR.DELETED_AT.isNull())
                        // The link's owner shares their own calendars -- the selection on
                        // creation is the share check.
                        .and(CALENDAR.OWNER_ID.eq(feed.getOwnerId()))
                        // And per event: an event someone gave a share of its own that
                        // leaves the owner out is not theirs to publish.
                        .and(visibility.itemVisibleTo(feed.getOwnerId(), CalendarSyncTypes.EVENT_TYPE, EVENT.ID))
                        .fetch(record -> new IcsWriter.Entry(
                                record.get(EVENT.ID) + "@hiwiski",
                                record.get(EVENT.TITLE),
                                record.get(EVENT.DESCRIPTION),
                                record.get(EVENT.LOCATION),
                                record.get(EVENT.TIME_FORM),
                                record.get(EVENT.STARTS_AT),
                                record.get(EVENT.ENDS_AT),
                                record.get(EVENT.START_DATE),
                                record.get(EVENT.END_DATE),
                                record.get(EVENT.LOCAL_START),
                                record.get(EVENT.LOCAL_END),
                                record.get(EVENT.TIME_ZONE),
                                record.get(EVENT.RRULE),
                                record.get(EVENT.EXCEPTIONS) == null
                                        ? null
                                        : record.get(EVENT.EXCEPTIONS).data(),
                                record.get(EVENT.UPDATED_AT),
                                busyOnly));

        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType("text/calendar;charset=UTF-8"))
                .body(writer.write(new IcsWriter.Feed(feed.getName(), entries)));
    }
}
