import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/common/recurrence.dart';
import 'package:hiwiski/domain/common/recurrence_spec.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

/// **"Until 10 October" ends on 10 October** — in the zone the series is in.
///
/// `UNTIL` was written as 23:59:59 UTC. In Berlin a daily 01:00 series then also ran
/// on the 11th; in New York a daily 20:00 series lost the 10th.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  List<DateTime> days(String time, String timeZone) {
    final hour = int.parse(time.split(':').first);
    final rrule = RecurrenceSpec(
      frequency: .daily,
      end: .until,
      until: DateTime(2026, 10, 10),
    ).toRrule();
    return const Recurrence().expand(
      rrule: rrule,
      start: DateTime(2026, 10, 7, hour),
      timeZone: timeZone,
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 20),
    );
  }

  test('a series ends on the chosen day, early or late in it', () {
    // The device's own zone: the one the chosen day is meant in. CI sets it via TZ.
    final timeZone = Platform.environment['TZ'] ?? 'Europe/Berlin';
    for (final time in ['01:00', '20:00']) {
      final occurrences = days(time, timeZone);
      expect(occurrences.last.day, equals(10), reason: '$time in $timeZone');
      expect(occurrences, hasLength(4), reason: '$time in $timeZone');
    }
  });

  // From a subscribed feed: COUNT and UNTIL together, which the parser rejects. The
  // event shows once instead of taking the whole view down.
  test('an unreadable rule shows the event once', () {
    final start = DateTime(2026, 10, 7, 9);
    expect(
      const Recurrence().expand(
        rrule: 'FREQ=WEEKLY;COUNT=5;UNTIL=20261231T000000Z',
        start: start,
        timeZone: 'Europe/Berlin',
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 11, 1),
      ),
      equals([start]),
    );
  });
}
