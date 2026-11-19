import '../../core/db/hiwiski_database.dart';
import '../../domain/calendar/calendar_items.dart';

/// An event row as the domain model — one mapping for the calendar and the reminders.
extension EventRowMapping on EventRow {
  CalendarEvent toDomain() => .new(
    id: id,
    ownerId: ownerId,
    version: version,
    deletedAt: deletedAt,
    calendarId: calendarId,
    entityKey: entityKey,
    title: title,
    description: description,
    location: location,
    timeForm: timeForm,
    startsAt: startsAt,
    endsAt: endsAt,
    startDate: startDate,
    endDate: endDate,
    localStart: localStart,
    localEnd: localEnd,
    timeZone: timeZone,
    rrule: rrule,
    exceptions: exceptions,
    attendees: attendees,
    tags: tags,
    reminderMinutes: reminderMinutes,
    sourceUid: sourceUid,
  );
}
