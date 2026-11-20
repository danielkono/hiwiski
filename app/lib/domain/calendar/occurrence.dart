import 'package:clock/clock.dart';

import 'dart:convert';

import '../common/match_groups.dart';
import '../common/recurrence.dart';
import '../common/rrule_parts.dart';
import '../../core/common/wire.dart';
import '../common/calendar_days.dart';
import 'calendar_items.dart';

/// A single occurrence of an event — what fills one row.
///
/// A series is **one** row in the database and **many** occurrences on screen. The
/// expansion happens afresh on every display and is not stored: stored occurrences would
/// have to be updated on every change to the rule, and that is exactly where the
/// calendar in an earlier version fell apart.
class Occurrence implements Comparable<Occurrence> {
  const Occurrence({
    required this.event,
    required this.start,
    required this.end,
    required this.allDay,
    this.originalStart,
    this.moved = false,
  });

  final CalendarEvent event;

  /// Local time. For all-day events the time is 00:00 and meaningless.
  final DateTime start;

  /// Local time, **inclusive** — "29.09.–10.10." ends on 10.10., not on the 11th.
  ///
  /// This differs from `DTEND` in the ICS standard, which is exclusive. The conversion
  /// happens where ICS is written and read, not here: in the UI, "up to and including"
  /// is what people mean.
  final DateTime end;

  final bool allDay;

  /// For a moved series occurrence, the original start — the key the exception is
  /// stored under.
  final DateTime? originalStart;

  final bool moved;

  String get id => event.id;

  bool get isSeries => (event.rrule ?? '').isNotEmpty;

  /// Whether the occurrence spans more than one day.
  ///
  /// The pinned strip shows all-day **and** multi-day events: "Summer holidays
  /// 29.09.–10.10." once with "from–to", not again on every day.
  bool get isMultiDay => dayKeyOf(end) > dayKeyOf(start);

  bool get isPinned => allDay || isMultiDay;

  DateTime get day => startOfDay(start);

  /// Whether the occurrence touches the given day.
  bool touches(DateTime date) {
    final target = dayKeyOf(date);
    return target >= dayKeyOf(start) && target <= dayKeyOf(end);
  }

  @override
  int compareTo(Occurrence other) {
    // Day first, then all-day events first within the day — they frame the day.
    // Sorting all-day first across all days put the holiday week starting Friday
    // ahead of today's event.
    final byDay = dayKeyOf(start).compareTo(dayKeyOf(other.start));
    if (byDay != 0) return byDay;
    if (allDay != other.allDay) return allDay ? -1 : 1;
    final byStart = start.compareTo(other.start);
    return byStart != 0 ? byStart : event.title.compareTo(other.event.title);
  }
}

/// A calendar day as a number, `20261010` — to compare days by.
///
/// Comparing days through `DateTime(year, month, day)` built a local date, and with it
/// a time zone lookup, on every comparison: sorting a month and asking every cell of the
/// grid which events touch it spent most of its time there.
int dayKeyOf(DateTime value) =>
    value.year * 10000 + value.month * 100 + value.day;

/// The occurrences of each day in `[from, to]`, by [dayKeyOf], in the order of
/// [occurrences] — a span under every day it covers.
///
/// Built once for a view instead of every day asking every occurrence.
Map<int, List<Occurrence>> occurrencesByDay(
  Iterable<Occurrence> occurrences,
  DateTime from,
  DateTime to,
) {
  final first = startOfDay(from);
  final last = dayKeyOf(to);
  final byDay = <int, List<Occurrence>>{};
  for (final item in occurrences) {
    DateTime day = startOfDay(item.start).isBefore(first)
        ? first
        : startOfDay(item.start);
    final end = dayKeyOf(item.end) < last ? dayKeyOf(item.end) : last;
    for (int key = dayKeyOf(day); key <= end; key = dayKeyOf(day)) {
      (byDay[key] ??= <Occurrence>[]).add(item);
      day = addDays(day, 1);
    }
  }
  return byDay;
}

/// Expands an event within a window.
///
/// Three time forms, three paths — each stores something different,
/// and so each one computes differently too.
class EventExpander {
  const EventExpander([this.recurrence = const Recurrence()]);

  final Recurrence recurrence;

  /// All occurrences in the half-open window `[from, to)`.
  List<Occurrence> expand(CalendarEvent event, DateTime from, DateTime to) {
    if (event.deletedAt != null) return const [];

    return switch (event.timeForm) {
      TimeForms.allDay => _allDay(event, from, to),
      TimeForms.recurring => _recurring(event, from, to),
      _ => _timed(event, from, to),
    };
  }

  List<Occurrence> _timed(CalendarEvent event, DateTime from, DateTime to) {
    final start = event.startsAt?.toLocal();
    if (start == null) return const [];
    final end = event.endsAt?.toLocal() ?? start;
    if (end.isBefore(from) || !start.isBefore(to)) return const [];
    return [Occurrence(event: event, start: start, end: end, allDay: false)];
  }

  List<Occurrence> _allDay(CalendarEvent event, DateTime from, DateTime to) {
    final start = event.startDate;
    if (start == null) return const [];
    final end = event.endDate ?? start;
    if ((event.rrule ?? '').isNotEmpty) {
      return _allDaySeries(event, start, end, from, to);
    }
    // The whole end day still counts.
    final endOfDay = DateTime(end.year, end.month, end.day, 23, 59, 59);
    if (endOfDay.isBefore(from) || !start.isBefore(to)) return const [];
    return [
      Occurrence(
        event: event,
        start: DateTime(start.year, start.month, start.day),
        end: DateTime(end.year, end.month, end.day),
        allDay: true,
      ),
    ];
  }

  /// A series of whole days — a birthday, a yearly holiday. Expanded over dates, each
  /// occurrence as long as the first; it used to show only once, on its first day,
  /// while still counting as a series.
  List<Occurrence> _allDaySeries(
    CalendarEvent event,
    DateTime start,
    DateTime end,
    DateTime from,
    DateTime to,
  ) {
    final first = startOfDay(start);
    final days = _days(first, startOfDay(end));
    final exceptions = decodeExceptions(event.exceptions);

    // The look-behind of a multi-day series: an occurrence that began before the
    // window may still run into it.
    final starts = recurrence.expand(
      rrule: event.rrule,
      start: first,
      timeZone: event.timeZone ?? utcTimeZone,
      from: addDays(startOfDay(from), -days),
      to: to,
    );

    final result = <Occurrence>[];
    final seen = <String>{};
    for (final day in starts) {
      seen.add(formatKey(day));
      final exception = exceptions[formatKey(day)];
      if (exception is Map &&
          exception[EventExceptionFields.cancelled] == true) {
        continue;
      }

      DateTime actualStart = day;
      DateTime actualEnd = addDays(day, days);
      bool moved = false;
      if (exception is Map) {
        final movedStart = _parseLocal(
          exception[EventExceptionFields.start] as String?,
        );
        if (movedStart != null) {
          actualStart = startOfDay(movedStart);
          final movedEnd = _parseLocal(
            exception[EventExceptionFields.end] as String?,
          );
          actualEnd = movedEnd == null
              ? addDays(actualStart, days)
              : startOfDay(movedEnd);
          moved = true;
        }
      }

      final endOfDay = addDays(actualEnd, 1);
      if (!endOfDay.isAfter(from) || !actualStart.isBefore(to)) continue;
      result.add(
        Occurrence(
          event: event,
          start: actualStart,
          end: actualEnd,
          allDay: true,
          originalStart: day,
          moved: moved,
        ),
      );
    }
    return result
      ..addAll(
        _movedIn(
          event,
          exceptions,
          seen,
          from,
          to,
          seed: first,
          zone: event.timeZone ?? utcTimeZone,
          length: (start) => addDays(start, days),
          allDay: true,
        ),
      )
      ..sort();
  }

  /// Whole days from [first] to [last], counted on the calendar — not as 24-hour
  /// stretches, which a daylight saving change would cut short.
  static int _days(DateTime first, DateTime last) => DateTime.utc(
    last.year,
    last.month,
    last.day,
  ).difference(DateTime.utc(first.year, first.month, first.day)).inDays;

  List<Occurrence> _recurring(CalendarEvent event, DateTime from, DateTime to) {
    final seed = _parseLocal(event.localStart);
    if (seed == null) return const [];
    final localEnd = _parseLocal(event.localEnd);
    final duration = localEnd == null
        ? Duration.zero
        : localEnd.difference(seed);
    final zone = event.timeZone ?? utcTimeZone;
    final exceptions = decodeExceptions(event.exceptions);

    // A window with a look-behind: an occurrence that starts before the window and
    // reaches into it belongs in it. Without the look-behind a multi-day series event
    // was missing from exactly the week it runs in.
    final lookBehind = duration > .zero ? duration : Duration.zero;

    final starts = recurrence.expand(
      rrule: event.rrule,
      start: seed,
      timeZone: zone,
      from: from.subtract(lookBehind),
      to: to,
    );

    final result = <Occurrence>[];
    final seen = <String>{};
    for (final start in starts) {
      final key = formatKey(start);
      seen.add(key);
      final exception = exceptions[key];

      if (exception is Map &&
          exception[EventExceptionFields.cancelled] == true) {
        continue;
      }

      DateTime actualStart = start;
      DateTime actualEnd = start.add(duration);
      bool moved = false;
      if (exception is Map) {
        final movedStart = _parseLocal(
          exception[EventExceptionFields.start] as String?,
        );
        if (movedStart != null) {
          actualStart = movedStart;
          actualEnd =
              _parseLocal(exception[EventExceptionFields.end] as String?) ??
              movedStart.add(duration);
          moved = true;
        }
      }

      if (actualEnd.isBefore(from) || !actualStart.isBefore(to)) continue;
      result.add(
        Occurrence(
          event: event,
          start: actualStart,
          end: actualEnd,
          allDay: false,
          originalStart: start,
          moved: moved,
        ),
      );
    }
    return result
      ..addAll(
        _movedIn(
          event,
          exceptions,
          seen,
          from,
          to,
          seed: seed,
          zone: zone,
          length: (start) => start.add(duration),
          allDay: false,
        ),
      )
      ..sort();
  }

  /// The occurrences moved **into** the window from an original start outside it —
  /// Monday's lesson moved to the Friday before. The expansion only reaches the
  /// original starts in the window, so these were never shown, and
  /// [occurrenceNear] fell back to another occurrence for them.
  ///
  /// Only a key that is a real occurrence of the rule counts; a stale one, left by a
  /// changed rule, does not.
  Iterable<Occurrence> _movedIn(
    CalendarEvent event,
    Map<String, dynamic> exceptions,
    Set<String> seen,
    DateTime from,
    DateTime to, {
    required DateTime seed,
    required String zone,
    required DateTime Function(DateTime start) length,
    required bool allDay,
  }) sync* {
    for (final MapEntry(:key, :value) in exceptions.entries) {
      if (seen.contains(key) || value is! Map) continue;
      if (value[EventExceptionFields.cancelled] == true) continue;
      final original = DateTime.tryParse(key);
      DateTime? start = _parseLocal(
        value[EventExceptionFields.start] as String?,
      );
      if (original == null || start == null) continue;
      DateTime end =
          _parseLocal(value[EventExceptionFields.end] as String?) ??
          length(start);
      if (allDay) {
        start = startOfDay(start);
        end = startOfDay(end);
      }
      final over = allDay ? !addDays(end, 1).isAfter(from) : end.isBefore(from);
      if (over || !start.isBefore(to)) continue;
      final real = recurrence.expand(
        rrule: event.rrule,
        start: seed,
        timeZone: zone,
        from: original,
        to: original.add(const Duration(seconds: 1)),
      );
      if (!real.contains(original)) continue;
      yield Occurrence(
        event: event,
        start: start,
        end: end,
        allDay: allDay,
        originalStart: original,
        moved: true,
      );
    }
  }

  /// The key of an exception: the **original** start, never a sequence number.
  ///
  /// A sequence number would shift as soon as someone changes the rule — and then the
  /// cancellation of 5 October would suddenly be the one of the 12th.
  static String formatKey(DateTime localStart) => localStamp(localStart);

  static Map<String, dynamic> decodeExceptions(String raw) {
    if (raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } on FormatException {
      // A broken column must not cost us the calendar.
      return {};
    }
  }

  static DateTime? _parseLocal(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}

/// How far a change to a series reaches.
///
/// "For a series event, saving asks: **only this event / this and all following / the
/// whole series.**"
enum SeriesScope { onlyThis, thisAndFollowing, wholeSeries }

/// Whether no occurrence of the series [event] comes before [originalStart] — then
/// "this and all following" from there is the whole series.
///
/// Cut off before its first occurrence, a series stayed behind as a live row that
/// expanded to nothing: found in search and links, "—" on its screen, and on an edit
/// its comments and shares stayed on the ghost.
bool nothingBefore(CalendarEvent event, DateTime originalStart) {
  final seed = event.timeForm == TimeForms.allDay
      ? event.startDate
      : DateTime.tryParse(event.localStart ?? '');
  if (seed == null || !seed.isBefore(originalStart)) return true;
  return const EventExpander()
      .expand(event, seed, originalStart)
      .every(
        (item) => !(item.originalStart ?? item.start).isBefore(originalStart),
      );
}

/// The rule of [event] for what is left of it from [from] on: a `COUNT` counts
/// only the occurrences not yet had.
String? remainingRule(CalendarEvent event, DateTime from) {
  final rrule = event.rrule;
  if (rrule == null) return null;
  final count = _count.firstMatch(rrule);
  final seed = event.timeForm == TimeForms.allDay
      ? event.startDate
      : DateTime.tryParse(event.localStart ?? '');
  if (count == null || seed == null) return rrule;
  final had = const Recurrence()
      .expand(
        rrule: rrule,
        start: seed,
        timeZone: event.timeZone ?? utcTimeZone,
        from: seed,
        to: from,
      )
      .length;
  return withCount(rrule, int.parse(count.groupOf(1)) - had);
}

/// [rrule] with its `COUNT` set to [count] — at least 1, since a series of none is
/// not one. A rule without a `COUNT` stays as it is.
String withCount(String rrule, int count) =>
    rrule.replaceFirst(_count, '${RruleParts.count}=${count < 1 ? 1 : count}');

/// The `COUNT` of a rule.
final _count = RegExp('${RruleParts.count}=(\\d+)', caseSensitive: false);

/// The occurrence one means when speaking of [event] — the one at [at] if given, else
/// the one around now; without one nearby the next, searched up to a year ahead, or
/// else the last of the year before. `null` for a series without a trace in that span.
Occurrence? occurrenceNear(CalendarEvent event, {DateTime? at}) {
  const expander = EventExpander();
  final anchor = at ?? clock.now();
  final around = expander.expand(
    event,
    addDays(startOfDay(anchor), -1),
    addDays(startOfDay(anchor), 2),
  );
  if (at != null) {
    final exact = around.where((item) => item.start == at).firstOrNull;
    if (exact != null) return exact;
  }
  if (around.isNotEmpty) return around.first;
  // The next one, not the last: expanding from 2000 and taking `.last` showed a
  // weekly series a year ahead, and a daily one from 2020 stopped at the expansion
  // limit somewhere in 2025. Only an ended series looks back, and only a year.
  final ahead = expander.expand(
    event,
    startOfDay(anchor),
    addDays(anchor, 366),
  );
  if (ahead.isNotEmpty) return ahead.first;
  final behind = expander.expand(event, addDays(anchor, -366), anchor);
  return behind.isEmpty ? null : behind.last;
}
