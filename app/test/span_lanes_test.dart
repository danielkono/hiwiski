import 'package:hiwiski/domain/calendar/occurrence.dart';
import 'package:hiwiski/domain/calendar/span_lanes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/calendar/calendar_items.dart';

/// **A multi-day event keeps its line from first day to last.**
///
/// When testing, the line of a long event broke where a second one began in the middle
/// of it: each day stacked its spans anew, and the first one jumped a row down.
void main() {
  Occurrence span(String id, DateTime first, DateTime last) => .new(
    event: CalendarEvent(
      id: id,
      ownerId: 'anna',
      version: 1,
      tags: '',
      calendarId: 'c1',
      title: id,
      timeForm: 'ALL_DAY',
      startDate: first,
      endDate: last,
      timeZone: 'Europe/Berlin',
      exceptions: '',
      attendees: '',
    ),
    start: first,
    end: last,
    allDay: true,
  );

  test('a span that begins inside another one gets the next lane, and the first keeps its own', () {
    final holidays = span(
      'holidays',
      DateTime(2026, 10, 5),
      DateTime(2026, 10, 16),
    );
    final trip = span('trip', DateTime(2026, 10, 8), DateTime(2026, 10, 10));

    final lanes = assignSpanLanes([trip, holidays]);

    expect(lanes[holidays], equals(0));
    expect(lanes[trip], equals(1));
  });

  test('a lane is free again the day after its span ends', () {
    final first = span('first', DateTime(2026, 10, 5), DateTime(2026, 10, 7));
    final second = span('second', DateTime(2026, 10, 8), DateTime(2026, 10, 9));
    final overlapping = span(
      'overlapping',
      DateTime(2026, 10, 7),
      DateTime(2026, 10, 8),
    );

    final lanes = assignSpanLanes([first, second, overlapping]);

    expect(lanes[first], equals(0));
    expect(lanes[overlapping], equals(1));
    // Begins after `first` ended: back in lane 0, not stacked below.
    expect(lanes[second], equals(0));
  });

  test(
    'lanes are per week: a span from last week does not push this one down',
    () {
      final lastWeek = span(
        'last',
        DateTime(2026, 9, 28),
        DateTime(2026, 10, 2),
      );
      final overlapping = span(
        'overlap',
        DateTime(2026, 9, 30),
        DateTime(2026, 10, 6),
      );
      final thisWeek = span(
        'this',
        DateTime(2026, 10, 7),
        DateTime(2026, 10, 9),
      );

      final lanes = assignSpanLanes(
        [lastWeek, overlapping, thisWeek],
        from: DateTime(2026, 10, 5),
        to: DateTime(2026, 10, 11),
      );

      // Last week's span is not in this week at all; the one reaching in takes lane 0,
      // and the next one, starting after it ended, takes lane 0 too.
      expect(lanes.containsKey(lastWeek), isFalse);
      expect(lanes[overlapping], equals(0));
      expect(lanes[thisWeek], equals(0));
    },
  );

  test('every span of a crowded week gets a lane — none is left out', () {
    final spans = [
      for (var i = 0; i < 4; i++)
        span('s$i', DateTime(2026, 10, 5), DateTime(2026, 10, 8 + i)),
    ];

    final lanes = assignSpanLanes(
      spans,
      from: DateTime(2026, 10, 5),
      to: DateTime(2026, 10, 11),
    );

    expect(lanes.values.toSet(), equals({0, 1, 2, 3}));
  });
}
