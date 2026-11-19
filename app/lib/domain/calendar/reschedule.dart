import '../common/calendar_days.dart';
import '../tags/tag.dart';
import 'calendar_items.dart';
import 'event_draft.dart';
import 'occurrence.dart';

/// Where something lands in the week view: a day, and a minute of it — or no minute,
/// for the band of all-day events above the hours.
class WeekSlot {
  const WeekSlot(this.day, [this.minute]);

  /// The day; its time of day is ignored.
  final DateTime day;

  /// Minutes from midnight; `null` for the all-day band.
  final int? minute;

  bool get allDay => minute == null;

  /// The moment the slot stands for — midnight in the all-day band.
  DateTime get start => .new(
    day.year,
    day.month,
    day.day,
    (minute ?? 0) ~/ 60,
    (minute ?? 0) % 60,
  );

  @override
  bool operator ==(Object other) =>
      other is WeekSlot && other.day == day && other.minute == minute;

  @override
  int get hashCode => Object.hash(day, minute);

  @override
  String toString() => 'WeekSlot($day, $minute)';
}

/// How long an event made in the week view lasts — by a tap into the hours, or an
/// all-day event dragged into them.
const weekDefaultMinutes = 30;

/// The grid things snap to in the week view.
const weekSnapMinutes = 15;

/// [minute] on the 15-minute grid, rounded down — what a tap or a drop means.
int snapToGrid(int minute) => (minute ~/ weekSnapMinutes * weekSnapMinutes)
    .clamp(0, 24 * 60 - weekSnapMinutes);

/// The time an occurrence gets when it is dropped on [slot].
///
/// - A timed event keeps its length and moves to the slot's start.
/// - An all-day event dropped on another day stays all-day, as long as it was.
/// - An all-day event dropped into the hours becomes a timed one of
///   [weekDefaultMinutes].
/// - A timed event dropped on the all-day band becomes an all-day event of that day.
///
/// In local time; whether it is stored as a moment or on the wall clock (a series) is
/// the caller's choice.
({DateTime start, DateTime end, bool allDay}) movedTime(
  Occurrence occurrence,
  WeekSlot slot,
) {
  final day = startOfDay(slot.day);
  // A timed event over several days stands in the band too: moved there, it keeps its
  // times and moves by whole days.
  if (slot.allDay && !occurrence.allDay && occurrence.isMultiDay) {
    final shift = dayKeyOf(day) - dayKeyOf(occurrence.start);
    DateTime moved(DateTime time) =>
        .new(time.year, time.month, time.day + shift, time.hour, time.minute);
    return (
      start: moved(occurrence.start),
      end: moved(occurrence.end),
      allDay: false,
    );
  }
  if (slot.allDay) {
    final days = occurrence.allDay
        ? dayKeyOf(occurrence.end) - dayKeyOf(occurrence.start)
        : 0;
    return (start: day, end: addDays(day, days), allDay: true);
  }
  final start = slot.start;
  final length = occurrence.allDay
      ? const Duration(minutes: weekDefaultMinutes)
      : _wall(occurrence.end).difference(_wall(occurrence.start));
  return (start: start, end: _local(_wall(start).add(length)), allDay: false);
}

/// Whether dropping [occurrence] on [slot] changes anything — a drop back where it
/// was writes nothing and asks nothing.
bool movesOccurrence(Occurrence occurrence, WeekSlot slot) {
  final moved = movedTime(occurrence, slot);
  return moved.allDay != occurrence.allDay ||
      moved.start != occurrence.start ||
      moved.end != occurrence.end;
}

/// The event as it is, as a draft at [time] — what the week view writes after a drop.
EventDraft draftOf(CalendarEvent event, EventTime time) => .new(
  title: event.title,
  time: time,
  description: event.description,
  location: event.location,
  rrule: (event.rrule ?? '').isEmpty ? null : event.rrule,
  attendees: tagIdsOf(event.attendees),
  tags: tagIdsOf(event.tags),
  reminderMinutes: event.reminderMinutes,
);

/// The time form for a moved occurrence: all-day, on the wall clock for a series, or
/// a moment.
EventTime timeOf(
  ({DateTime start, DateTime end, bool allDay}) moved, {
  required bool series,
}) => switch ((moved.allDay, series)) {
  (true, _) => AllDayEvent(moved.start, moved.end),
  (false, true) => RecurringEvent(moved.start, moved.end),
  (false, false) => TimedEvent(moved.start, moved.end),
};

/// The time of a **whole series** after one of its occurrences was moved: the series
/// keeps its first date and moves by as many days as the occurrence did, and takes
/// over the new time of day and length.
EventTime seriesTimeAfterMove(
  CalendarEvent event,
  Occurrence occurrence,
  ({DateTime start, DateTime end, bool allDay}) moved,
) {
  final first = switch ((event.localStart, event.startDate, event.startsAt)) {
    (final local?, _, _) => DateTime.tryParse(local),
    (_, final date?, _) => date,
    (_, _, final at?) => at.toLocal(),
    _ => null,
  };
  final seed = first ?? occurrence.start;
  final shift = dayKeyOf(moved.start) - dayKeyOf(occurrence.start);
  final start = moved.allDay
      ? DateTime(seed.year, seed.month, seed.day + shift)
      : DateTime(
          seed.year,
          seed.month,
          seed.day + shift,
          moved.start.hour,
          moved.start.minute,
        );
  final length = _wall(moved.end).difference(_wall(moved.start));
  final end = _local(_wall(start).add(length));
  return moved.allDay ? AllDayEvent(start, end) : RecurringEvent(start, end);
}

/// A wall-clock time as a UTC value: arithmetic on it is free of daylight saving.
DateTime _wall(DateTime time) =>
    .utc(time.year, time.month, time.day, time.hour, time.minute, time.second);

DateTime _local(DateTime wall) =>
    .new(wall.year, wall.month, wall.day, wall.hour, wall.minute, wall.second);
