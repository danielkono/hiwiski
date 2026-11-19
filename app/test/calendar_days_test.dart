import 'package:hiwiski/domain/common/calendar_days.dart';
import 'package:flutter_test/flutter_test.dart';

/// Days are counted in days, not in durations.
///
/// The bug was in the month grid and only showed up when clicking through: October 2026
/// showed the 25th twice, and the 26th — a Monday — stood in the Tuesday column.
///
/// ```
/// M   T   W   T   F   S   S
/// 19  20  21  22  23  24  25
/// 25  26  27  28  29  30  31      ← this is what it looked like
/// ```
///
/// Cause: `DateTime(2026, 10, 19).add(const Duration(days: 7))`. On 25 October the clocks
/// go back, the day has 25 hours, and a `Duration` is absolute time — seven times 24
/// hours land at 23:00 of the previous day.
/// Whether this machine's zone changes the clocks on 25 October 2026.
final bool _shiftsClocks =
    DateTime(2026, 10, 25).timeZoneOffset !=
    DateTime(2026, 10, 26).timeZoneOffset;

void main() {
  // The 2026 clock changes in Central Europe: 29 March (forward) and 25 October (back).
  final backward = DateTime(2026, 10, 25);
  final forward = DateTime(2026, 3, 29);

  test('a week across the fall-back change lands on the same weekday', () {
    final monday = DateTime(2026, 10, 19);
    expect(monday.weekday, equals(DateTime.monday));

    final next = addDays(monday, 7);
    expect(next, equals(DateTime(2026, 10, 26)));
    expect(next.weekday, equals(DateTime.monday));
  });

  test('a week across the spring-forward change lands on the same weekday', () {
    final monday = DateTime(2026, 3, 23);
    final next = addDays(monday, 7);
    expect(next, equals(DateTime(2026, 3, 30)));
    expect(next.weekday, equals(DateTime.monday));
  });

  test(
    'this is what the bug looked like — and no longer does',
    () {
      // `Duration` slips here, `addDays` does not.
      expect(
        // The bug, on purpose.
        // ignore: many_lints/avoid_dst_unsafe_date_arithmetic
        DateTime(2026, 10, 19).add(const Duration(days: 7)),
        isNot(DateTime(2026, 10, 26)),
      );
      expect(
        addDays(DateTime(2026, 10, 19), 7),
        equals(DateTime(2026, 10, 26)),
      );
    },
    // Only meaningful where there is a clock change. In UTC — and so possibly on the
    // build server — `Duration` calculates correctly too, and the test would assert
    // something that does not hold in that place at all. The remaining cases check
    // `addDays` in **every** zone.
    // ignore: many_lints/avoid_skipped_tests
    skip: _shiftsClocks ? null : 'no clock change in this zone',
  );

  test('a month grid across the fall-back change has 42 distinct days', () {
    final start = startOfWeek(DateTime(2026, 10));
    final days = [for (var i = 0; i < 42; i++) addDays(start, i)];

    expect(days.toSet(), hasLength(42));
    // Column fidelity: every cell of a column carries the same weekday.
    for (int column = 0; column < 7; column++) {
      final weekdays = [
        for (var week = 0; week < 6; week++) days[week * 7 + column].weekday,
      ];
      expect(weekdays.toSet(), hasLength(1));
    }
  });

  test('startOfWeek returns the Monday', () {
    for (final day in daysBetween(
      DateTime(2026, 10, 19),
      DateTime(2026, 10, 26),
    )) {
      expect(startOfWeek(day), equals(DateTime(2026, 10, 19)));
    }
  });

  test('daysBetween does not skip a day at a clock change', () {
    final backwardWeek = daysBetween(
      addDays(backward, -3),
      addDays(backward, 4),
    ).toList();
    expect(backwardWeek, hasLength(7));
    expect(backwardWeek.toSet(), hasLength(7));

    final forwardWeek = daysBetween(
      addDays(forward, -3),
      addDays(forward, 4),
    ).toList();
    expect(forwardWeek, hasLength(7));
    expect(forwardWeek.toSet(), hasLength(7));
  });

  test('addDays normalizes across month and year boundaries', () {
    expect(addDays(DateTime(2026, 1, 31), 1), equals(DateTime(2026, 2)));
    expect(addDays(DateTime(2026, 12, 31), 1), equals(DateTime(2027)));
    expect(addDays(DateTime(2026, 3), -1), equals(DateTime(2026, 2, 28)));
  });

  // In a year starting on a Thursday, every summer week came out one too low:
  // 7 October 2026 is in week 41, not 40.
  test('the ISO week across summer time', () {
    expect(isoWeekNumber(DateTime(2026, 10, 7)), equals(41));
    expect(isoWeekNumber(DateTime(2026, 4)), equals(14));
    expect(isoWeekNumber(DateTime(2026)), equals(1));
    expect(isoWeekNumber(DateTime(2027)), equals(53));
  });
}
