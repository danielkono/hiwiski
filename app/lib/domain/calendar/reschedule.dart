import '../common/calendar_days.dart';
import '../common/recurrence.dart';
import '../common/recurrence_spec.dart';
import '../common/rrule_parts.dart';
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
    final shift = daysFrom(occurrence.start, day);
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
        ? daysFrom(occurrence.start, occurrence.end)
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

/// What [time] spans, in the form [movedTime] gives — what the editor sets for an
/// occurrence, read as where it was moved to.
({DateTime start, DateTime end, bool allDay}) spanOf(EventTime time) =>
    switch (time) {
      AllDayEvent(:final start, :final end) => (
        start: start,
        end: end,
        allDay: true,
      ),
      RecurringEvent(:final start, :final end) ||
      TimedEvent(
        :final start,
        :final end,
      ) => (start: start, end: end, allDay: false),
    };

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

/// A series after one of its occurrences was dropped elsewhere in the week view.
class const SeriesMove({
  /// From its new start on, with the new time of day and length.
  required final EventTime time,
  required final String? rrule,

  /// Where an exception of the series, by its original start, stands afterwards —
  /// `null` for the dropped occurrence's own: the drop has put it in place.
  required final DateTime? Function(DateTime original) carry,

  /// Occurrences the new rule yields that the series never had — cancelled with the
  /// move (see [seriesAfterMove]).
  final List<DateTime> cancelled = const [],
});

/// A series after [occurrence] was dropped at [moved]: the whole series, or with
/// [from] what is left of it from there on ("this and all following").
///
/// A rule that repeats by its start — weekly without weekdays, monthly on a date —
/// moves its start by as many days as the occurrence moved.
///
/// A rule that names its days changes as [ruleAfterMove] says, and the start stays
/// in its week or month. It becomes the first day the new rule yields: a start on a
/// day the rule does not hold is counted differently by different calendars. A
/// Thursday series whose start had moved to the Friday kept its `BYDAY=TH` and had
/// nothing in that week: the dropped event was gone.
///
/// Where the dragged weekday moves before weekdays the rule kept, the new start lies
/// before those — and in that first week they came only after the old start, so
/// there they are cancelled. Otherwise "this and all following" from a Friday to the
/// Tuesday showed that week's Wednesday twice: in the old part and in the new one.
SeriesMove seriesAfterMove(
  CalendarEvent event,
  Occurrence occurrence,
  ({DateTime start, DateTime end, bool allDay}) moved, {
  DateTime? from,
}) {
  final first = switch ((event.localStart, event.startDate, event.startsAt)) {
    (final local?, _, _) => DateTime.tryParse(local),
    (_, final date?, _) => date,
    (_, _, final at?) => at.toLocal(),
    _ => null,
  };
  final seed = from ?? first ?? occurrence.start;
  final base = from == null ? event.rrule : remainingRule(event, from);
  final original = occurrence.originalStart ?? occurrence.start;
  final rrule = ruleAfterMove(base, original: original, target: moved.start);
  final length = _wall(moved.end).difference(_wall(moved.start));
  DateTime atNewTime(DateTime day) => moved.allDay
      ? startOfDay(day)
      : .new(
          day.year,
          day.month,
          day.day,
          moved.start.hour,
          moved.start.minute,
        );
  EventTime timeFrom(DateTime start) {
    final end = _local(_wall(start).add(length));
    return moved.allDay ? AllDayEvent(start, end) : RecurringEvent(start, end);
  }

  if (rrule == null || rrule == base) {
    // Counted from the day the rule gave the occurrence, as the rule above is: one
    // already moved off it and dropped back there leaves the series where it is.
    final days = daysFrom(original, moved.start);
    final start = from == null ? atNewTime(addDays(seed, days)) : moved.start;
    final shift = _wall(start).difference(_wall(seed));
    return SeriesMove(
      time: timeFrom(start),
      rrule: base,
      carry: (key) => key == from ? null : _local(_wall(key).add(shift)),
    );
  }

  final zone = event.timeZone ?? utcTimeZone;
  final spec = RecurrenceSpec.parse(rrule);
  final weekly = spec.frequency == .weekly;
  final lost = original.weekday;
  final gained = moved.start.weekday;
  // The first occurrence on the dragged weekday is in the start's own week when that
  // weekday does not come before the start; moved to before the start, it begins
  // the series. A monthly rule's start goes to its month's occurrence.
  final candidate = atNewTime(switch (weekly) {
    true when lost >= seed.weekday && gained < seed.weekday => addDays(
      seed,
      gained - seed.weekday,
    ),
    true => seed,
    false => DateTime(seed.year, seed.month),
  });
  List<DateTime> yields(DateTime start, DateTime until) =>
      const Recurrence().expand(
        rrule: rrule,
        start: start,
        timeZone: zone,
        from: start,
        to: until,
      );
  // Up to the next week or month the rule runs in: the first occurrence lies there
  // at the latest.
  final period = spec.interval + 1;
  final start =
      yields(
        candidate,
        weekly
            ? addDays(candidate, DateTime.daysPerWeek * period)
            : DateTime(candidate.year, candidate.month + period),
      ).firstOrNull ??
      candidate;
  final cancelled = [
    if (weekly && daysFrom(start, seed) > 0)
      for (final day in yields(start, startOfDay(seed)))
        if (daysFrom(start, day) > 0) day,
  ];
  return SeriesMove(
    time: timeFrom(start),
    // A cancelled occurrence still counts towards a `COUNT`.
    rrule: cancelled.isEmpty
        ? rrule
        : withCount(rrule, (spec.count ?? 0) + cancelled.length),
    carry: (key) {
      if (key == from) return null;
      if (weekly) {
        return atNewTime(
          key.weekday == lost ? addDays(key, gained - lost) : key,
        );
      }
      // The new rule's occurrence in the exception's month.
      return yields(start, DateTime(key.year, key.month + 1))
          .where((day) => day.year == key.year && day.month == key.month)
          .firstOrNull;
    },
    cancelled: cancelled,
  );
}

/// The rule of a series after its occurrence at [original] was dropped on [target]:
/// **only the day that was dragged moves.**
///
/// - Weekly on named weekdays, the occurrence's weekday becomes the target's: on
///   Monday and Wednesday, a Monday dragged to Tuesday leaves Tuesday and Wednesday.
/// - Monthly on an nth weekday, it becomes the target's: the second Tuesday dragged
///   to the next day, the second Wednesday — the last stays the last where the
///   target is the last of its weekday too.
///
/// Any other rule repeats by its start and comes back as it is; so does one the
/// editor does not understand, which is not rewritten blindly.
String? ruleAfterMove(
  String? rrule, {
  required DateTime original,
  required DateTime target,
}) {
  if (rrule == null || !RecurrenceSpec.understands(rrule)) return rrule;
  if (daysFrom(original, target) == 0) return rrule;
  final spec = RecurrenceSpec.parse(rrule);
  final String days;
  switch (spec) {
    case RecurrenceSpec(frequency: .weekly, :final weekdays)
        when weekdays.isNotEmpty:
      if (original.weekday == target.weekday) return rrule;
      final moved = {...weekdays}
        ..remove(original.weekday)
        ..add(target.weekday);
      days = (moved.toList()..sort()).map(RecurrenceSpec.dayCode).join(',');
    case RecurrenceSpec(frequency: .monthly, monthlyMode: .nthWeekday):
      final daysInMonth = DateTime(target.year, target.month + 1, 0).day;
      final nth =
          spec.nth == -1 && target.day + DateTime.daysPerWeek > daysInMonth
          ? -1
          : RecurrenceSpec.nthOfMonth(target);
      days = '$nth${RecurrenceSpec.dayCode(target.weekday)}';
    case _:
      return rrule;
  }
  return [
    for (final part in rrule.split(';'))
      part.toUpperCase().startsWith('${RruleParts.byDay}=')
          ? '${RruleParts.byDay}=$days'
          : part,
  ].join(';');
}

/// A wall-clock time as a UTC value: arithmetic on it is free of daylight saving.
DateTime _wall(DateTime time) =>
    .utc(time.year, time.month, time.day, time.hour, time.minute, time.second);

DateTime _local(DateTime wall) =>
    .new(wall.year, wall.month, wall.day, wall.hour, wall.minute, wall.second);
