package de.danielkononov.hiwiski.calendar.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.CALENDAR;
import static de.danielkononov.hiwiski.db.generated.Tables.CALENDAR_FEED;
import static de.danielkononov.hiwiski.db.generated.Tables.CALENDAR_SUBSCRIPTION;
import static de.danielkononov.hiwiski.db.generated.Tables.EVENT;

import de.danielkononov.hiwiski.access.AccessLevel;
import de.danielkononov.hiwiski.access.JooqOwnable;
import de.danielkononov.hiwiski.access.Ownable;
import de.danielkononov.hiwiski.admin.JooqRestorable;
import de.danielkononov.hiwiski.admin.JooqTokenCarryOver;
import de.danielkononov.hiwiski.admin.RestoreCarryOver;
import de.danielkononov.hiwiski.admin.Restorable;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;
import org.jooq.DSLContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** What {@code calendar} registers with {@code access} and {@code admin}. */
@Configuration
class CalendarOwnables {

    @Bean
    Ownable calendarOwnable(DSLContext db) {
        return new JooqOwnable(db, CalendarSyncTypes.CALENDAR_TYPE, CALENDAR);
    }

    @Bean
    Ownable eventOwnable(DSLContext db) {
        return new JooqOwnable(
                db, CalendarSyncTypes.EVENT_TYPE, EVENT, CalendarSyncTypes.CALENDAR_TYPE, EVENT.CALENDAR_ID) {

            @Override
            public List<UUID> assigneesOf(UUID itemId) {
                UUID[] values =
                        db().select(EVENT.ATTENDEES).from(EVENT).where(EVENT.ID.eq(itemId)).fetchOne(EVENT.ATTENDEES);
                return values == null ? List.of() : Arrays.asList(values);
            }

            @Override
            public List<UUID> ownerAssigneesOf(UUID itemId) {
                return uuids(itemId, EVENT.OWNER_ASSIGNEES);
            }

            @Override
            public java.util.Optional<String> assigneeField() {
                return java.util.Optional.of("attendees");
            }

            @Override
            public void assignmentWritten(UUID itemId, java.util.Collection<UUID> chosenByOwner) {
                keepOwnerAssignees(itemId, EVENT.ATTENDEES, EVENT.OWNER_ASSIGNEES, chosenByOwner);
            }

            @Override
            public List<UUID> assignedTo(UUID subject) {
                return db().select(EVENT.ID)
                        .from(EVENT)
                        .where(EVENT.ATTENDEES.contains(new UUID[] {subject}))
                        .and(EVENT.DELETED_AT.isNull())
                        .fetch(EVENT.ID);
            }

            /**
             * For events, an assignment grants <em>read</em>, not <em>check off</em>.
             *
             * <p>An event has no done state — there would be nothing to check off, and
             * the level would otherwise only allow what it cannot do anyway.
             */
            @Override
            public AccessLevel assignmentLevel() {
                return AccessLevel.READ;
            }
        };
    }

    @Bean
    Ownable calendarSubscriptionOwnable(DSLContext db) {
        return new JooqOwnable(
                db,
                CalendarSyncTypes.SUBSCRIPTION_TYPE,
                CALENDAR_SUBSCRIPTION,
                CalendarSyncTypes.CALENDAR_TYPE,
                CALENDAR_SUBSCRIPTION.CALENDAR_ID) {

            /**
             * Only into one's own calendar: the app always creates a fresh one with it,
             * and one attached to someone else's calendar imported in its creator's name
             * and could be removed only with that calendar.
             */
            @Override
            public boolean placedByContainerOwnerOnly() {
                return true;
            }
        };
    }

    @Bean
    Ownable calendarFeedOwnable(DSLContext db) {
        return new JooqOwnable(db, CalendarSyncTypes.FEED_TYPE, CALENDAR_FEED) {

            @Override
            public boolean shareable() {
                return false;
            }
        };
    }

    @Bean
    Restorable calendarRestorable(DSLContext db) {
        return new JooqRestorable(db, CalendarSyncTypes.CALENDAR_TYPE, CALENDAR, CALENDAR.NAME, null, null, null);
    }

    @Bean
    Restorable eventRestorable(DSLContext db) {
        return new JooqRestorable(
                db,
                CalendarSyncTypes.EVENT_TYPE,
                EVENT,
                EVENT.TITLE,
                EVENT.ENTITY_KEY,
                EVENT.CALENDAR_ID,
                CALENDAR);
    }

    /**
     * A feed's address survives a restore as it is now: one replaced after a leak must
     * not come back with an older archive.
     */
    @Bean
    RestoreCarryOver calendarFeedTokens(DSLContext db) {
        return new JooqTokenCarryOver(db, CALENDAR_FEED, CALENDAR_FEED.ID, CALENDAR_FEED.TOKEN);
    }
}
