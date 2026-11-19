import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/calendar/event_draft.dart';

/// **"Whole series" from one occurrence keeps the series' own first date** and
/// carries over only what was changed on the occurrence.
void main() {
  test('an unchanged occurrence leaves the series as it was', () {
    final time =
        RecurringEvent(
          DateTime(2026, 10, 12, 17),
          DateTime(2026, 10, 12, 18),
        ).reseed(
          seriesStart: DateTime(2026, 1, 5, 17),
          opened: DateTime(2026, 10, 12, 17),
        );
    expect(time.start, equals(DateTime(2026, 1, 5, 17)));
    expect(time.end, equals(DateTime(2026, 1, 5, 18)));
  });

  test('a later start and a longer length move the whole series', () {
    // Opened in October (summer time), the series begins in January (winter time):
    // the shift is an hour on the wall clock either way.
    final time =
        RecurringEvent(
          DateTime(2026, 10, 12, 18),
          DateTime(2026, 10, 12, 20),
        ).reseed(
          seriesStart: DateTime(2026, 1, 5, 17),
          opened: DateTime(2026, 10, 12, 17),
        );
    expect(time.start, equals(DateTime(2026, 1, 5, 18)));
    expect(time.end, equals(DateTime(2026, 1, 5, 20)));
  });

  test('a series of whole days keeps its first day', () {
    final time = AllDayEvent(
      DateTime(2026, 3, 14),
      DateTime(2026, 3, 15),
    ).reseed(seriesStart: DateTime(2020, 3, 14), opened: DateTime(2026, 3, 14));
    expect(time.start, equals(DateTime(2020, 3, 14)));
    expect(time.end, equals(DateTime(2020, 3, 15)));
  });
}
