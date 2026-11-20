import 'package:flutter/foundation.dart';

import 'match_groups.dart';
import 'rrule_parts.dart';

/// How often.
enum RecurrenceFrequency { daily, weekly, monthly, yearly }

/// Monthly in two ways: "on the 14th" or "on the second Tuesday".
enum MonthlyMode { dayOfMonth, nthWeekday }

/// How long.
enum RecurrenceEnd { never, count, until }

/// A recurrence rule in the shape the dialog edits it in.
///
/// **The dialog has to be able to do what the server and the expansion can do**:
/// interval, weekdays, nth weekday of the month, `COUNT` and `UNTIL`.
/// An earlier version only offered daily/weekly/monthly/yearly and gave away the rest — and whoever
/// cannot enter "take out the trash every two weeks" does not enter it at all.
///
/// What gets stored is still an `RRULE` string: it is the format ICS exports and
/// imports, and a format of our own would be a second truth.
@immutable
class RecurrenceSpec {
  const RecurrenceSpec({
    this.frequency = RecurrenceFrequency.weekly,
    this.interval = 1,
    this.weekdays = const {},
    this.monthlyMode = MonthlyMode.dayOfMonth,
    this.nth = 1,
    this.nthWeekday = DateTime.monday,
    this.end = RecurrenceEnd.never,
    this.count,
    this.until,
  });

  final RecurrenceFrequency frequency;

  /// "every 2 weeks". At least 1.
  final int interval;

  /// For `WEEKLY`: the chosen days, as `DateTime.monday` … `DateTime.sunday`.
  final Set<int> weekdays;

  final MonthlyMode monthlyMode;

  /// 1…4 or `-1` for "last".
  final int nth;

  final int nthWeekday;

  final RecurrenceEnd end;

  final int? count;

  /// As a local date, without a time.
  final DateTime? until;

  RecurrenceSpec copyWith({
    RecurrenceFrequency? frequency,
    int? interval,
    Set<int>? weekdays,
    MonthlyMode? monthlyMode,
    int? nth,
    int? nthWeekday,
    RecurrenceEnd? end,
    int? count,
    DateTime? until,
  }) => .new(
    frequency: frequency ?? this.frequency,
    interval: interval ?? this.interval,
    weekdays: weekdays ?? this.weekdays,
    monthlyMode: monthlyMode ?? this.monthlyMode,
    nth: nth ?? this.nth,
    nthWeekday: nthWeekday ?? this.nthWeekday,
    end: end ?? this.end,
    count: count ?? this.count,
    until: until ?? this.until,
  );

  // --- To RRULE -----------------------------------------------------------------

  static const _dayCodes = {
    DateTime.monday: 'MO',
    DateTime.tuesday: 'TU',
    DateTime.wednesday: 'WE',
    DateTime.thursday: 'TH',
    DateTime.friday: 'FR',
    DateTime.saturday: 'SA',
    DateTime.sunday: 'SU',
  };

  /// The code of [weekday] (`DateTime.monday` … `DateTime.sunday`) in a rule: `MO`.
  static String dayCode(int weekday) => _dayCodes[weekday] ?? _monday;

  /// `BYDAY` with an ordinal: `2FR`, `-1MO`.
  static final _ordinal = RegExp(r'^(-?\d)([A-Z]{2})$');
  static final _leadingOrdinal = RegExp(r'^-?\d');
  static final _prefix = RegExp('^${RruleParts.prefix}', caseSensitive: false);
  static final _date = RegExp(r'^(\d{4})(\d{2})(\d{2})');

  static const _dayNumbers = {
    'MO': DateTime.monday,
    'TU': DateTime.tuesday,
    'WE': DateTime.wednesday,
    'TH': DateTime.thursday,
    'FR': DateTime.friday,
    'SA': DateTime.saturday,
    'SU': DateTime.sunday,
  };

  String toRrule() {
    final parts = <String>[
      '${RruleParts.freq}=${switch (frequency) {
        .daily => RruleParts.daily,
        .weekly => RruleParts.weekly,
        .monthly => RruleParts.monthly,
        .yearly => RruleParts.yearly,
      }}',
    ];

    if (interval > 1) parts.add('${RruleParts.interval}=$interval');

    if (frequency == .weekly && weekdays.isNotEmpty) {
      final ordered = weekdays.toList()..sort();
      parts.add(
        '${RruleParts.byDay}=${ordered.map((day) => _dayCodes[day]).join(',')}',
      );
    }

    if (frequency == .monthly && monthlyMode == .nthWeekday) {
      parts.add('${RruleParts.byDay}=$nth${_dayCodes[nthWeekday]}');
    }

    switch (end) {
      case .never:
        break;
      case .count:
        if (count != null) parts.add('${RruleParts.count}=$count');
      case .until:
        // In the standard `UNTIL` is a UTC instant. Here the chosen day is included up
        // to its end — otherwise the last event would drop out, and nobody understands
        // why the series ends a day too early.
        if (until case final until?) {
          parts.add('${RruleParts.until}=${untilValue(until)}');
        }
    }

    // **Without an `RRULE:` prefix.** That is the form the server stores, and thus
    // the only one that counts. With the prefix the ICS export contained
    // `RRULE:RRULE:FREQ=WEEKLY` — and another calendar program then does not read the
    // series at all. Whoever needs the rule as a line adds the prefix when writing.
    return parts.join(';');
  }

  static String _pad(int value, int width) =>
      value.toString().padLeft(width, '0');

  // --- From RRULE ---------------------------------------------------------------

  /// Reads a rule back into the dialog.
  ///
  /// What is not understood is not invented: a rule with `BYSETPOS` or `BYMONTH` comes
  /// back as the default, and the dialog would overwrite it on save. That is why there
  /// is [understands] — the UI shows a foreign rule as text instead of mangling it.
  static RecurrenceSpec parse(String rrule) {
    final values = _values(rrule);

    final frequency = switch (values[RruleParts.freq]) {
      RruleParts.daily => RecurrenceFrequency.daily,
      RruleParts.monthly => RecurrenceFrequency.monthly,
      RruleParts.yearly => RecurrenceFrequency.yearly,
      _ => RecurrenceFrequency.weekly,
    };

    final byDay = values[RruleParts.byDay];
    Set<int> weekdays = <int>{};
    MonthlyMode monthlyMode = .dayOfMonth;
    int nth = 1;
    int nthWeekday = DateTime.monday;

    if (byDay != null && byDay.isNotEmpty) {
      final entries = byDay.split(',');
      final ordinal = _ordinal.firstMatch(entries.firstOrNull ?? '');
      if (ordinal != null && frequency == .monthly) {
        monthlyMode = MonthlyMode.nthWeekday;
        nth = int.parse(ordinal.groupOf(1));
        nthWeekday = _dayNumbers[ordinal.groupOf(2)] ?? DateTime.monday;
      } else {
        weekdays = {for (final entry in entries) ?_dayNumbers[entry]};
      }
    }

    final count = int.tryParse(values[RruleParts.count] ?? '');
    final until = _parseUntil(values[RruleParts.until]);

    return RecurrenceSpec(
      frequency: frequency,
      interval: int.tryParse(values[RruleParts.interval] ?? '') ?? 1,
      weekdays: weekdays,
      monthlyMode: monthlyMode,
      nth: nth,
      nthWeekday: nthWeekday,
      end: switch ((count, until)) {
        (_?, _) => RecurrenceEnd.count,
        (null, _?) => RecurrenceEnd.until,
        (null, null) => RecurrenceEnd.never,
      },
      count: count,
      until: until,
    );
  }

  /// Whether the dialog fully represents this rule.
  ///
  /// A rule it does not represent it must not save: it would come back truncated, and
  /// "every second Friday of the quarter" would silently turn into something else.
  static bool understands(String rrule) {
    const known = {
      RruleParts.freq,
      RruleParts.interval,
      RruleParts.byDay,
      RruleParts.count,
      RruleParts.until,
      RruleParts.weekStart,
    };
    final values = _values(rrule);
    if (!values.keys.every(known.contains)) return false;
    // The keys alone said nothing about their values: `FREQ=HOURLY;INTERVAL=4` passed,
    // the dialog showed "every 4 weeks", and saving wrote exactly that.
    if (!_frequencies.contains(values[RruleParts.freq])) return false;
    // The dialog has no field for the week start and writes none: saved, a `WKST=SU`
    // rule every second week moved its Sunday occurrences by a week. Monday is the
    // default anyway, so only that one is safe to drop.
    final weekStart = values[RruleParts.weekStart];
    if (weekStart != null && weekStart.toUpperCase() != _monday) return false;

    final byDay = values[RruleParts.byDay];
    if (byDay == null) return true;
    final freq = values[RruleParts.freq];
    final entries = byDay.split(',');
    if (entries.any(_leadingOrdinal.hasMatch)) {
      // An nth weekday: exactly one, and only monthly.
      return entries.length == 1 && freq == RruleParts.monthly;
    }
    return freq == RruleParts.weekly;
  }

  static const _monday = 'MO';

  /// The frequencies the dialog offers.
  static const _frequencies = {
    RruleParts.daily,
    RruleParts.weekly,
    RruleParts.monthly,
    RruleParts.yearly,
  };

  static Map<String, String> _values(String rrule) {
    final clean = rrule.replaceFirst(_prefix, '');
    return {
      for (final part in clean.split(';'))
        if (part.contains('='))
          part.split('=').first.toUpperCase(): part.split('=').last,
    };
  }

  /// The `UNTIL` value for "up to and including [day]": the end of that day **here**,
  /// as the UTC instant the standard wants.
  ///
  /// It used to be `<day>T235959Z` — the end of the day in UTC, not here. Converted back
  /// into the series' zone, a daily 01:00 series in Berlin gained an occurrence on the
  /// day after, and a 20:00 series in New York lost the one on the last day.
  static String untilValue(DateTime day) =>
      untilInstant(DateTime(day.year, day.month, day.day, 23, 59, 59));

  /// Which of its weekday in the month [day] is: 1 to 4, or -1 for the last.
  ///
  /// Never 5: the dialog offers first to fourth and last. Days 29 to 31 are always the
  /// last of their weekday — counted as the fifth, the label read "first Tuesday" while
  /// the rule said `5TU`, and months without a fifth one were skipped.
  static int nthOfMonth(DateTime day) {
    final nth = ((day.day - 1) ~/ 7) + 1;
    return nth > 4 ? -1 : nth;
  }

  /// [moment] — a local time — as an `UNTIL` value: the UTC instant the standard wants.
  static String untilInstant(DateTime moment) {
    final end = moment.toUtc();
    return '${_pad(end.year, 4)}${_pad(end.month, 2)}${_pad(end.day, 2)}'
        '${RruleParts.timeSeparator}'
        '${_pad(end.hour, 2)}${_pad(end.minute, 2)}${_pad(end.second, 2)}'
        '${RruleParts.utc}';
  }

  static DateTime? _parseUntil(String? raw) {
    if (raw == null) return null;
    final match = _date.firstMatch(raw);
    if (match == null) return null;
    final date = DateTime(
      int.parse(match.groupOf(1)),
      int.parse(match.groupOf(2)),
      int.parse(match.groupOf(3)),
    );
    final instant = _instant.firstMatch(raw);
    // A date only, or the old end-of-day-in-UTC form: the date is the one meant.
    if (instant == null || raw.endsWith(RruleParts.endOfDay)) return date;
    // An instant: the day it falls on here — the end of the chosen day, read back.
    final local = DateTime.utc(
      date.year,
      date.month,
      date.day,
      int.parse(instant.groupOf(1)),
      int.parse(instant.groupOf(2)),
      int.parse(instant.groupOf(3)),
    ).toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static final _instant = RegExp(r'T(\d{2})(\d{2})(\d{2})Z$');

  @override
  bool operator ==(Object other) =>
      other is RecurrenceSpec &&
      other.frequency == frequency &&
      other.interval == interval &&
      setEquals(other.weekdays, weekdays) &&
      other.monthlyMode == monthlyMode &&
      other.nth == nth &&
      other.nthWeekday == nthWeekday &&
      other.end == end &&
      other.count == count &&
      other.until == until;

  @override
  int get hashCode => Object.hash(
    frequency,
    interval,
    Object.hashAllUnordered(weekdays),
    monthlyMode,
    nth,
    nthWeekday,
    end,
    count,
    until,
  );
}
