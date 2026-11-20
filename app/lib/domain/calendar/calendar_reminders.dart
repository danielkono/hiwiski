import '../../core/common/wire.dart';
import '../common/calendar_days.dart';

/// The reminder an event has in effect, in minutes before the start — `null` for none.
///
/// Its own, otherwise its calendar's default. Like the calendar's tags the default is
/// applied here rather than copied onto the events: events that already exist get it
/// too, and changing it on the calendar takes effect at once. An event that should stay
/// silent in such a calendar says so with [ReminderMinutes.none].
int? effectiveReminder(int? own, int? calendarDefault) {
  if (own == ReminderMinutes.none) return null;
  return own ?? calendarDefault;
}

/// The words a reminder's text needs, in the device's language — handed in by whoever
/// knows the language.
class const ReminderWords({
  required final String today,
  required final String tomorrow,
  required final String allDay,

  /// A day further off: "Tue, 27.10.".
  required final String Function(DateTime day) date,
});

/// When the event a reminder is for takes place, as the notification says it:
/// "Today, 10:00–11:00", "Tomorrow · All day", "Tue, 27.10., 18:30".
///
/// A bare "10:00" left open which day, and a reminder set a day ahead read as if the
/// event were today; an all-day event said "00:00".
///
/// "Today" and "tomorrow" are told from [shownAt], the moment the notification
/// appears, not from when it is scheduled: the text is fixed when the reminder is
/// handed to the system, often days before. Counted from then, a reminder scheduled
/// the evening before said "Tomorrow, 08:00" when it rang at 07:30 on the day itself.
String reminderWhen(
  ({DateTime start, DateTime end, bool allDay}) occurrence, {
  required DateTime shownAt,
  required ReminderWords words,
}) {
  final (:start, :end, :allDay) = occurrence;
  final today = startOfDay(shownAt);
  final day = switch (startOfDay(start)) {
    final day when day == today => words.today,
    final day when day == addDays(today, 1) => words.tomorrow,
    final day => words.date(day),
  };
  if (allDay) return '$day · ${words.allDay}';
  final from = _clock(start);
  // Ending on another day, the end alone would mislead.
  final sameDay = startOfDay(end) == startOfDay(start);
  return sameDay && end.isAfter(start)
      ? '$day, $from–${_clock(end)}'
      : '$day, $from';
}

String _clock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';
