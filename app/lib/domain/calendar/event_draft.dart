/// When an event takes place — exactly one of three time forms.
///
/// Only the fields of the chosen form are stored; the others are cleared. Otherwise
/// switching from "all day" back to "with time" would leave a start date behind, and
/// two time forms would fight over the same event.
sealed class EventTime {
  const EventTime();
}

/// At a moment in time: stored in UTC.
final class TimedEvent extends EventTime {
  const TimedEvent(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

/// Whole days, without a time and without a zone.
final class AllDayEvent extends EventTime {
  const AllDayEvent(this.start, this.end);

  /// The first and the last day; the time of day is ignored.
  final DateTime start;
  final DateTime end;

  /// What a "whole series" edit made from one opened occurrence writes back — as
  /// [RecurringEvent.reseed], in whole days.
  AllDayEvent reseed({
    required DateTime seriesStart,
    required DateTime opened,
  }) {
    final shift = _wall(_day(start)).difference(_wall(_day(opened)));
    final length = _wall(_day(end)).difference(_wall(_day(start)));
    final newStart = _local(_wall(_day(seriesStart)).add(shift));
    return AllDayEvent(newStart, _local(_wall(newStart).add(length)));
  }

  static DateTime _day(DateTime time) => .new(time.year, time.month, time.day);
}

/// A series on the wall clock: "every Monday 8:00" stays 8:00 across the daylight
/// saving change; computed in UTC it would shift to 9:00. Stored as local time plus
/// the device's zone.
final class RecurringEvent extends EventTime {
  const RecurringEvent(this.start, this.end);

  final DateTime start;
  final DateTime end;

  /// What a "whole series" edit made from one opened occurrence writes back: the
  /// series keeps its own first date, and only what was changed on the occurrence —
  /// shifted start, new length — is carried over.
  ///
  /// The editor starts from the occurrence that was opened. Writing its start as the
  /// series' start re-seeded the series there, and every earlier occurrence was gone.
  /// Computed on the wall clock, so a shift across the daylight saving change stays
  /// what the member saw.
  RecurringEvent reseed({
    required DateTime seriesStart,
    required DateTime opened,
  }) {
    final shift = _wall(start).difference(_wall(opened));
    final length = _wall(end).difference(_wall(start));
    final newStart = _local(_wall(seriesStart).add(shift));
    return RecurringEvent(newStart, _local(_wall(newStart).add(length)));
  }
}

/// Everything the event editor sets — the whole event as the member wrote it.
class EventDraft {
  const EventDraft({
    required this.title,
    required this.time,
    this.description,
    this.location,
    this.rrule,
    this.attendees = const [],
    this.tags = const [],
    this.reminderMinutes,
  });

  final String title;
  final EventTime time;
  final String? description;
  final String? location;

  /// The repeat rule — `null` for a single event.
  final String? rrule;

  /// Members and groups.
  final List<String> attendees;
  final List<String> tags;

  /// Minutes before the start — `null` for none of its own (the calendar's default
  /// applies), `ReminderMinutes.none` for none at all.
  final int? reminderMinutes;

  /// The same draft at another [time].
  EventDraft withTime(EventTime time) => .new(
    title: title,
    time: time,
    description: description,
    location: location,
    rrule: rrule,
    attendees: attendees,
    tags: tags,
    reminderMinutes: reminderMinutes,
  );

  /// The same event once, detached from its series: no repeat rule, and a series'
  /// wall-clock time becomes a time of its own.
  EventDraft single() => .new(
    title: title,
    time: switch (time) {
      RecurringEvent(:final start, :final end) => TimedEvent(start, end),
      final other => other,
    },
    description: description,
    location: location,
    attendees: attendees,
    tags: tags,
    reminderMinutes: reminderMinutes,
  );
}

/// A wall-clock time as a UTC value: arithmetic on it is free of daylight saving.
DateTime _wall(DateTime time) =>
    .utc(time.year, time.month, time.day, time.hour, time.minute, time.second);

DateTime _local(DateTime wall) =>
    .new(wall.year, wall.month, wall.day, wall.hour, wall.minute, wall.second);
