import '../tags/tag.dart';
import 'calendar_items.dart';

/// The tags an event carries in effect: its own plus those of its calendar.
///
/// A calendar's tags apply to all of its events — including imported and subscribed
/// ones, which nobody tags one by one. They are added here rather than copied onto the
/// events, so changing them on the calendar takes effect at once.
String effectiveEventTags(CalendarEvent event, Calendar? calendar) =>
    combinedEventTags(event.tags, calendar?.tags);

/// [effectiveEventTags] on the stored, comma-separated values.
String combinedEventTags(String eventTags, String? calendarTags) {
  if (calendarTags == null || calendarTags.isEmpty) return eventTags;
  final ids = {...tagIdsOf(eventTags), ...tagIdsOf(calendarTags)};
  return ids.join(',');
}
