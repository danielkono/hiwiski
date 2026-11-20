/// Arithmetic in **days**, not durations.
///
/// `DateTime(2026, 10, 19).add(const Duration(days: 7))` gives, in local time,
/// **October 25 at 23:00**, not the 26th at 00:00: on that day the clocks go back,
/// the day has 25 hours, and a `Duration` is absolute time.
///
/// In the month grid it looked like this — the 25th appeared twice, and the 26th
/// slipped into the Tuesday column:
///
/// ```
/// M   T   W   T   F   S   S
/// 19  20  21  22  23  24  25
/// 25  26  27  28  29  30  31
/// ```
///
/// Exactly the bug a series computed in UTC has — just one level
/// up: not in the series, but in the grid that shows it. That is why the arithmetic
/// lives here once and not in seven places.
library;

export '../../core/common/wire.dart' show utcTimeZone;

const _dateTimeSeparator = 'T';

/// A wall-clock date as the wire carries it: `2026-10-05`.
String localDate(DateTime value) =>
    '${_pad(value.year, 4)}-${_pad(value.month, 2)}-${_pad(value.day, 2)}';

/// A wall-clock date-time without a zone, as the wire carries `localStart`:
/// `2026-10-05T18:30`.
String localStamp(DateTime value) =>
    '${localDate(value)}$_dateTimeSeparator'
    '${_pad(value.hour, 2)}:${_pad(value.minute, 2)}';

String _pad(int value, int width) => value.toString().padLeft(width, '0');

/// The start of the day, without a time.
DateTime startOfDay(DateTime value) => .new(value.year, value.month, value.day);

/// [days] calendar days later — the same day across any clock change.
///
/// `DateTime(y, m, d + n)` normalizes month and year boundaries itself and leaves the
/// time at 00:00; so there is no hour that could shift.
DateTime addDays(DateTime value, int days) =>
    .new(value.year, value.month, value.day + days);

/// How many calendar days [to] lies after [from] — negative before it; the time of
/// day does not count.
///
/// Counted on UTC dates, which no clock change cuts short. The difference of two
/// day numbers like `20261031` is no count of days: from 31 October to 1 November
/// it is 70.
int daysFrom(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// All days from [from] (inclusive) to [to] (exclusive).
Iterable<DateTime> daysBetween(DateTime from, DateTime to) sync* {
  for (
    DateTime day = startOfDay(from);
    day.isBefore(to);
    day = addDays(day, 1)
  ) {
    yield day;
  }
}

/// The Monday of the week [value] falls in.
DateTime startOfWeek(DateTime value) =>
    addDays(value, DateTime.monday - value.weekday);

/// ISO 8601: the week with the year's first Thursday is week 1.
///
/// Counted on UTC dates: between local midnights, a span across the switch to summer
/// time is an hour short of whole days, `inDays` rounded down, and in a year starting
/// on a Thursday — 2026 — every summer week came out one too low.
int isoWeekNumber(DateTime day) {
  final date = DateTime.utc(day.year, day.month, day.day);
  final thursday = date.add(Duration(days: DateTime.thursday - date.weekday));
  final firstOfYear = DateTime.utc(thursday.year);
  return (thursday.difference(firstOfYear).inDays ~/ 7) + 1;
}
