import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/calendar/occurrence.dart';
import 'package:hiwiski/domain/calendar/week_layout.dart';
import 'package:hiwiski/domain/calendar/calendar_items.dart';
import 'package:hiwiski/domain/common/calendar_days.dart';

/// **The week view shows only the hours that hold something** — and skips long empty
/// stretches, so a whole week fits at once.
void main() {
  final monday = DateTime(2026, 10, 5);
  final days = [for (var i = 0; i < 7; i++) addDays(monday, i)];

  Occurrence at(
    String id,
    DateTime start,
    DateTime end, {
    bool allDay = false,
  }) => .new(
    event: CalendarEvent(
      id: id,
      ownerId: 'anna',
      version: 1,
      tags: '',
      calendarId: 'c1',
      title: id,
      timeForm: allDay ? 'ALL_DAY' : 'SINGLE',
      timeZone: 'Europe/Berlin',
      exceptions: '',
      attendees: '',
    ),
    start: start,
    end: end,
    allDay: allDay,
  );

  test('the empty morning and evening are cut off, on full hours', () {
    final layout = WeekLayout.of(days, [
      at(
        'dentist',
        DateTime(2026, 10, 5, 9, 30),
        DateTime(2026, 10, 5, 10, 15),
      ),
      at('school', DateTime(2026, 10, 7, 8), DateTime(2026, 10, 7, 9)),
    ]);

    expect(layout.segments, equals([const TimeSegment(8 * 60, 11 * 60)]));
  });

  test(
    'a long empty stretch between two busy ones is skipped, a short one is not',
    () {
      final layout = WeekLayout.of(days, [
        at('breakfast', DateTime(2026, 10, 5, 7), DateTime(2026, 10, 5, 8)),
        at('lunch', DateTime(2026, 10, 6, 9), DateTime(2026, 10, 6, 10)),
        at('dinner', DateTime(2026, 10, 8, 18), DateTime(2026, 10, 8, 19)),
      ]);

      // 8:00–9:00 is one free hour — it stays; 10:00–18:00 is skipped.
      expect(
        layout.segments,
        equals([
          const TimeSegment(7 * 60, 10 * 60),
          const TimeSegment(18 * 60, 19 * 60),
        ]),
      );
    },
  );

  test('overlapping events share the day, side by side', () {
    final layout = WeekLayout.of(days, [
      at('a', DateTime(2026, 10, 5, 9), DateTime(2026, 10, 5, 11)),
      at('b', DateTime(2026, 10, 5, 10), DateTime(2026, 10, 5, 12)),
      at('c', DateTime(2026, 10, 5, 11), DateTime(2026, 10, 5, 12)),
      at('later', DateTime(2026, 10, 5, 14), DateTime(2026, 10, 5, 15)),
    ]);
    final pieces = {
      for (final piece in layout.pieces[0]) piece.occurrence.id: piece,
    };

    expect(pieces['a']!.column, equals(0));
    expect(pieces['b']!.column, equals(1));
    // Begins when `a` ends: back in the first column.
    expect(pieces['c']!.column, equals(0));
    expect([
      pieces['a']!.columns,
      pieces['b']!.columns,
      pieces['c']!.columns,
    ], equals([2, 2, 2]));
    // On its own again: the full width.
    expect(pieces['later']!.columns, equals(1));
  });

  test('all-day and multi-day events stay out of the hours', () {
    final layout = WeekLayout.of(days, [
      at('holidays', monday, DateTime(2026, 10, 9), allDay: true),
      at('trip', DateTime(2026, 10, 6, 18), DateTime(2026, 10, 7, 10)),
    ]);

    expect(layout.segments, isEmpty);
  });

  test('an event without an end still gets a block to tap', () {
    final layout = WeekLayout.of(days, [
      at('call', DateTime(2026, 10, 5, 8), DateTime(2026, 10, 5, 8)),
    ]);

    expect(
      layout.pieces[0].single.end - layout.pieces[0].single.start,
      equals(WeekLayout.minLength),
    );
  });
}
