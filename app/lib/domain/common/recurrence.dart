import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:rrule/rrule.dart';
import 'package:timezone/timezone.dart' as tz;

import 'match_groups.dart';
import 'rrule_parts.dart';

/// Expands a recurrence rule — **in local time**.
///
/// "Every Monday 8:00" stays 8:00, even across a clock change; computed in UTC it
/// would shift to 9:00. That is exactly why the `RECURRING` time form has its own
/// fields with `local_start` and `time_zone`.
///
/// It is checked against `golden/recurrence.json` — **the same file the server checks
/// against.** Two libraries that behave differently in edge cases are not two opinions
/// you can leave standing side by side: an event the phone shows on Monday and the
/// server on Tuesday is worse than no recurrence at all.
class Recurrence {
  const Recurrence();

  /// The maximum number of occurrences returned.
  ///
  /// A rule without `COUNT` and without `UNTIL` is infinite; the window limits it, but
  /// a very large window must not keep the device busy.
  static const maxOccurrences = 2000;

  /// How many instances one expansion may step through at most — the server's
  /// `MAX_STEPS`.
  ///
  /// Instances before the window count too: a rule whose occurrences mostly fall
  /// outside it must not keep the UI isolate busy.
  static const maxSteps = 100000;

  /// All occurrences in the half-open window `[from, to)`, as local time.
  ///
  /// The computation uses *naive* timestamps: local time is treated as if it were UTC.
  /// That is not a side trick but exactly the semantics a series needs — it hangs on
  /// the wall calendar, not on an instant.
  List<DateTime> expand({
    required String? rrule,
    required DateTime start,
    required String timeZone,
    required DateTime from,
    required DateTime to,
  }) {
    if (rrule == null || rrule.trim().isEmpty) {
      // No rule means: exactly once, on the start date.
      return (!start.isBefore(from) && start.isBefore(to)) ? [start] : const [];
    }

    if (!expandable(rrule)) {
      // A rule the `rrule` package would search through without yielding — for
      // minutes, or until it overflows. The server
      // refuses it on sync and drops it on import; one that arrived before shows
      // once, on its start, like an unreadable rule.
      if (kDebugMode) debugPrint('hiwiski: rule not expanded: "$rrule"');
      return (!start.isBefore(from) && start.isBefore(to)) ? [start] : const [];
    }

    final RecurrenceRule rule;
    try {
      rule = RecurrenceRule.fromString(_normalize(rrule, timeZone));
    } on Object catch (error) {
      // Anything, not only a `FormatException`: the package checks some values with
      // assertions, and an `AssertionError` took the whole view down in a debug build.
      //
      // A rule the parser rejects — from a subscribed feed, say: `COUNT` and `UNTIL`
      // together, an unknown FREQ. It used to throw out of the whole view; now the
      // event shows once, on its start, like an event without a rule. The zone already
      // has such a fallback.
      if (kDebugMode) debugPrint('hiwiski: unreadable rule "$rrule": $error');
      return (!start.isBefore(from) && start.isBefore(to)) ? [start] : const [];
    }
    if (_neverOccurs(rule)) return const [];
    final seed = _closeTo(rule, _naive(start), _naive(from));

    final location = _location(timeZone);
    final result = <DateTime>[];
    int steps = 0;
    DateTime? previous;
    for (final instance in rule.getInstances(start: seed)) {
      if (++steps > maxSteps) break;
      // The `rrule` package does not step `FREQ=SECONDLY` on: it yields the first
      // instance forever, and the loop never ended. A series that does not move on
      // ends where it stands.
      if (previous != null && !instance.isAfter(previous)) break;
      previous = instance;
      final local = _wallClock(location, instance);
      if (local.isBefore(from)) continue;
      if (!local.isBefore(to)) break;
      result.add(local);
      if (result.length >= maxOccurrences) break;
    }
    return result;
  }

  /// Whether [rrule] is one the devices can expand: the same list the server checks
  /// before it stores a rule, against the same file (`golden/recurrence-limits.json`).
  ///
  /// The `rrule` package searches period by period, up to the year 9999, for a set
  /// that matches, and yields nothing meanwhile — no step limit or clock in this loop
  /// sees it, and the package cannot be interrupted. `FREQ=HOURLY;BYWEEKNO=53;BYMONTH=6`
  /// took more than a minute per expansion, `FREQ=HOURLY;INTERVAL=24;BYHOUR=5` from a
  /// start at 4:00 13 s until the date overflowed. An isolate with a timeout would not
  /// help the web app, which has none; so such rules are not expanded at all:
  ///
  /// - no `SECONDLY`;
  /// - `BYWEEKNO` and `BYYEARDAY` only with `YEARLY`, `BYSETPOS` only with `WEEKLY`,
  ///   `MONTHLY` or `YEARLY`, a numbered `BYDAY` (`2TU`) only with `MONTHLY` or
  ///   `YEARLY` — RFC 5545 forbids most of the rest;
  /// - with `BYHOUR` (hourly) or `BYHOUR`/`BYMINUTE` (minutely), only an interval
  ///   that reaches every hour of the day or every minute of the hour: the package
  ///   steps by the interval until the hour or minute matches.
  ///
  /// - an `INTERVAL` only as a whole number from 1 on: with 0 the package never moves
  ///   on from its first period.
  ///
  /// The parts are read from the text, as the server does.
  static bool expandable(String rrule) {
    final parts = <String, String>{};
    for (final part in rrule.trim().replaceFirst(_prefix, '').split(';')) {
      final equals = part.indexOf('=');
      final name = (equals < 0 ? part : part.substring(0, equals))
          .trim()
          .toUpperCase();
      parts[name] = equals < 0 ? '' : part.substring(equals + 1);
    }
    final freq = parts[RruleParts.freq]?.trim().toUpperCase();
    if (freq == RruleParts.secondly) return false;
    // With an interval of 0 the package never moves on from its first period; one
    // that is no number it refuses with an error, not an exception.
    if (parts[RruleParts.interval] case final stated?) {
      if (!_positiveNumber.hasMatch(stated.trim())) return false;
    }
    final yearly = freq == RruleParts.yearly;
    final monthlyOrYearly = yearly || freq == RruleParts.monthly;
    if ((parts.containsKey(RruleParts.byWeekNumber) ||
            parts.containsKey(RruleParts.byYearDay)) &&
        !yearly) {
      return false;
    }
    if (parts.containsKey(RruleParts.bySetPosition) &&
        !(monthlyOrYearly || freq == RruleParts.weekly)) {
      return false;
    }
    if (!monthlyOrYearly &&
        _numberedDay.hasMatch(parts[RruleParts.byDay] ?? '')) {
      return false;
    }
    final interval =
        int.tryParse((parts[RruleParts.interval] ?? '').trim()) ?? 1;
    if (freq == RruleParts.hourly &&
        parts.containsKey(RruleParts.byHour) &&
        interval.gcd(_hoursPerDay) != 1) {
      return false;
    }
    return !(freq == RruleParts.minutely &&
        (parts.containsKey(RruleParts.byHour) ||
            parts.containsKey(RruleParts.byMinute)) &&
        (interval >= _minutesPerHour || interval.gcd(_minutesPerHour) != 1));
  }

  static final _numberedDay = RegExp('[0-9]');

  /// A whole number from 1 on, short enough to be one.
  static final _positiveNumber = RegExp(r'^0*[1-9][0-9]{0,8}$');
  static const _hoursPerDay = 24;
  static const _minutesPerHour = 60;

  /// A start for the expansion **just before the window**, on the series' own beat.
  ///
  /// The expansion used to begin at the series' first occurrence and step past every
  /// one before the window: a minutely rule started 26 years back took 14 s per call,
  /// on every reader's device. A rule with a fixed
  /// period — seconds up to weeks, which in naive time never change their length — is
  /// moved forward by a whole number of periods instead, so every instance it yields is
  /// one the series has. Months and years differ in length and stay as they are; they
  /// take few steps anyway. A rule with `COUNT` counts from its first occurrence and
  /// cannot be moved — the step limit bounds it; so is a weekly one with `BYSETPOS`.
  static DateTime _closeTo(RecurrenceRule rule, DateTime seed, DateTime from) {
    if (rule.count != null) return seed;
    // A week that starts at the seed is cut short until the week start: `BYSETPOS`
    // would count in a different set there than the series does.
    if (rule.frequency == .weekly && rule.hasBySetPositions) return seed;
    final unit = _periodOf(rule.frequency);
    if (unit == null) return seed;
    // A margin, because an occurrence in a clock-change gap moves on by the gap: it can
    // start a little before the window and land in it.
    final margin = rule.frequency > .daily ? _subDailyMargin : _dailyMargin;
    final target = from.subtract(margin);
    if (!target.isAfter(seed)) return seed;
    final period = unit * rule.actualInterval;
    final periods =
        target.difference(seed).inMicroseconds ~/ period.inMicroseconds;
    return seed.add(period * periods);
  }

  static Duration? _periodOf(Frequency frequency) => switch (frequency) {
    .secondly => const Duration(seconds: 1),
    .minutely => const Duration(minutes: 1),
    .hourly => const Duration(hours: 1),
    .daily => const Duration(days: 1),
    .weekly => const Duration(days: 7),
    _ => null,
  };

  static const _subDailyMargin = Duration(hours: 3);
  static const _dailyMargin = Duration(days: 1);

  /// A rule that has no occurrence at all — `BYMONTH=2;BYMONTHDAY=30`.
  ///
  /// The `rrule` package looks for one up to the year 9999, which took two seconds per
  /// call; it yields nothing in between, so the step limit does not catch it.
  static bool _neverOccurs(RecurrenceRule rule) {
    if (!rule.hasByMonthDays) return false;
    final months = rule.hasByMonths
        ? rule.byMonths
        : [for (int month = 1; month <= 12; month++) month];
    final longest = months
        .map((month) => _daysIn[month - 1])
        .reduce((a, b) => a > b ? a : b);
    return rule.byMonthDays.every((day) => day.abs() > longest);
  }

  /// The most days each month can have — February in a leap year.
  static const _daysIn = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

  /// The wall-clock time an occurrence has **in the series' zone**.
  ///
  /// A time that does not exist there — 02:30 on the day the clocks go forward — moves
  /// on by the gap, as the server does. Built as a device-local `DateTime`, the answer
  /// depended on the device's zone instead: 03:30 on a phone in Berlin, 02:30 on one in
  /// UTC, for the same Berlin series.
  static DateTime _wallClock(tz.Location location, DateTime naive) {
    final inZone = tz.TZDateTime(
      location,
      naive.year,
      naive.month,
      naive.day,
      naive.hour,
      naive.minute,
      naive.second,
    );
    return DateTime(
      inZone.year,
      inZone.month,
      inZone.day,
      inZone.hour,
      inZone.minute,
      inZone.second,
    );
  }

  static DateTime _naive(DateTime value) => .utc(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
    value.second,
  );

  /// Brings `UNTIL` onto the same arithmetic as the rest.
  ///
  /// In the standard `UNTIL` is a real UTC instant, but the rest of the expansion runs
  /// in naive local time here. Without this conversion a series would end an hour too
  /// early or too late depending on the season — and only sometimes, which is the
  /// worst kind of bug.
  static final _prefix = RegExp('^${RruleParts.prefix}');
  static final _utcUntil = RegExp(r'UNTIL=(\d{8}T\d{6})Z');

  static String _normalize(String rrule, String timeZone) {
    final clean = rrule.replaceFirst(_prefix, '');
    final match = _utcUntil.firstMatch(clean);
    if (match == null) return '${RruleParts.prefix}$clean';

    final utc = DateTime.parse('${match.groupOf(1)}${RruleParts.utc}');
    final location = _location(timeZone);
    final local = tz.TZDateTime.from(utc, location);
    final asNaive =
        '${local.year.toString().padLeft(4, '0')}'
        '${local.month.toString().padLeft(2, '0')}'
        '${local.day.toString().padLeft(2, '0')}${RruleParts.timeSeparator}'
        '${local.hour.toString().padLeft(2, '0')}'
        '${local.minute.toString().padLeft(2, '0')}'
        '${local.second.toString().padLeft(2, '0')}${RruleParts.utc}';
    final until = '${RruleParts.until}=$asNaive';
    return '${RruleParts.prefix}${clean.replaceFirst(match.groupOf(0), until)}';
  }

  static tz.Location _location(String timeZone) {
    try {
      return tz.getLocation(timeZone);
    } catch (_) {
      // An unknown zone must not cost the view: UTC is off, but at least the events
      // are there.
      return tz.UTC;
    }
  }
}
