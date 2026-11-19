import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/calendar/calendar_items.dart';
import 'package:hiwiski/domain/calendar/event_draft.dart';
import 'package:hiwiski/domain/calendar/occurrence.dart';
import 'package:hiwiski/domain/calendar/reschedule.dart';

/// **Moving events in the week view**: what a drop on a slot
/// makes of an event.
void main() {
  CalendarEvent event({
    String timeForm = 'TIMED',
    String? rrule,
    String? localStart,
    DateTime? startDate,
  }) => .new(
    id: 'e1',
    ownerId: 'anna',
    version: 1,
    tags: 'tag-a,tag-b',
    calendarId: 'c1',
    title: 'Dentist',
    location: 'Main Street',
    timeForm: timeForm,
    rrule: rrule,
    localStart: localStart,
    startDate: startDate,
    exceptions: '',
    attendees: 'ben',
    reminderMinutes: 15,
  );

  Occurrence timed(DateTime start, DateTime end, {CalendarEvent? of}) =>
      .new(event: of ?? event(), start: start, end: end, allDay: false);

  Occurrence allDay(DateTime start, DateTime end) => .new(
    event: event(timeForm: 'ALL_DAY'),
    start: start,
    end: end,
    allDay: true,
  );

  group('snapToGrid', () {
    test('rounds down to a quarter hour', () {
      expect(snapToGrid(8 * 60 + 14), equals(8 * 60));
      expect(snapToGrid(8 * 60 + 15), equals(8 * 60 + 15));
      expect(snapToGrid(8 * 60 + 59), equals(8 * 60 + 45));
    });

    test('stays inside the day', () {
      expect(snapToGrid(-5), equals(0));
      expect(snapToGrid(24 * 60), equals(24 * 60 - 15));
    });
  });

  group('movedTime', () {
    test('a timed event keeps its length', () {
      final moved = movedTime(
        timed(DateTime(2026, 10, 12, 8), DateTime(2026, 10, 12, 9, 30)),
        WeekSlot(DateTime(2026, 10, 14), 14 * 60 + 15),
      );
      expect(moved.allDay, isFalse);
      expect(moved.start, equals(DateTime(2026, 10, 14, 14, 15)));
      expect(moved.end, equals(DateTime(2026, 10, 14, 15, 45)));
    });

    test('an all-day event moved to another day stays all-day and as long', () {
      final moved = movedTime(
        allDay(DateTime(2026, 10, 12), DateTime(2026, 10, 13)),
        WeekSlot(DateTime(2026, 10, 15)),
      );
      expect(moved.allDay, isTrue);
      expect(moved.start, equals(DateTime(2026, 10, 15)));
      expect(moved.end, equals(DateTime(2026, 10, 16)));
    });

    test('an all-day event dropped into the hours lasts 30 minutes', () {
      final moved = movedTime(
        allDay(DateTime(2026, 10, 12), DateTime(2026, 10, 12)),
        WeekSlot(DateTime(2026, 10, 12), 10 * 60),
      );
      expect(moved.allDay, isFalse);
      expect(moved.start, equals(DateTime(2026, 10, 12, 10)));
      expect(moved.end, equals(DateTime(2026, 10, 12, 10, 30)));
    });

    test('a timed event dropped on the band becomes an all-day one', () {
      final moved = movedTime(
        timed(DateTime(2026, 10, 12, 8), DateTime(2026, 10, 12, 9)),
        WeekSlot(DateTime(2026, 10, 13)),
      );
      expect(moved.allDay, isTrue);
      expect(moved.start, equals(DateTime(2026, 10, 13)));
      expect(moved.end, equals(DateTime(2026, 10, 13)));
    });

    test('a timed event over several days keeps its times in the band', () {
      final moved = movedTime(
        timed(DateTime(2026, 10, 12, 18), DateTime(2026, 10, 14, 10)),
        WeekSlot(DateTime(2026, 10, 13)),
      );
      expect(moved.allDay, isFalse);
      expect(moved.start, equals(DateTime(2026, 10, 13, 18)));
      expect(moved.end, equals(DateTime(2026, 10, 15, 10)));
    });

    test('across the clock change the length stays on the wall clock', () {
      // 25 October 2026: Berlin goes back an hour.
      final moved = movedTime(
        timed(DateTime(2026, 10, 24, 8), DateTime(2026, 10, 24, 10)),
        WeekSlot(DateTime(2026, 10, 25), 8 * 60),
      );
      expect(moved.start, equals(DateTime(2026, 10, 25, 8)));
      expect(moved.end, equals(DateTime(2026, 10, 25, 10)));
    });
  });

  test('a drop back where it was moves nothing', () {
    final occurrence = timed(
      DateTime(2026, 10, 12, 8),
      DateTime(2026, 10, 12, 9),
    );
    expect(
      movesOccurrence(occurrence, WeekSlot(DateTime(2026, 10, 12), 8 * 60)),
      isFalse,
    );
    expect(
      movesOccurrence(occurrence, WeekSlot(DateTime(2026, 10, 12), 9 * 60)),
      isTrue,
    );
  });

  test('the draft keeps everything but the time', () {
    final draft = draftOf(
      event(rrule: 'FREQ=WEEKLY'),
      TimedEvent(DateTime(2026, 10, 12, 8), DateTime(2026, 10, 12, 9)),
    );
    expect(draft.title, equals('Dentist'));
    expect(draft.location, equals('Main Street'));
    expect(draft.rrule, equals('FREQ=WEEKLY'));
    expect(draft.attendees, equals(['ben']));
    expect(draft.tags, equals(['tag-a', 'tag-b']));
    expect(draft.reminderMinutes, equals(15));
  });

  group('seriesTimeAfterMove', () {
    test('the series keeps its first date and takes the new time', () {
      final series = event(
        rrule: 'FREQ=WEEKLY',
        localStart: '2026-09-07T08:00:00',
      );
      // The occurrence of 12 October, moved to Wednesday 14:00.
      final occurrence = timed(
        DateTime(2026, 10, 12, 8),
        DateTime(2026, 10, 12, 9),
        of: series,
      );
      final time = seriesTimeAfterMove(
        series,
        occurrence,
        movedTime(occurrence, WeekSlot(DateTime(2026, 10, 14), 14 * 60)),
      );
      expect(time, isA<RecurringEvent>());
      final recurring = time as RecurringEvent;
      expect(recurring.start, equals(DateTime(2026, 9, 9, 14)));
      expect(recurring.end, equals(DateTime(2026, 9, 9, 15)));
    });

    test('an all-day series moves by days', () {
      final series = event(
        timeForm: 'ALL_DAY',
        rrule: 'FREQ=WEEKLY',
        startDate: DateTime(2026, 9, 7),
      );
      final occurrence = Occurrence(
        event: series,
        start: DateTime(2026, 10, 12),
        end: DateTime(2026, 10, 12),
        allDay: true,
      );
      final time = seriesTimeAfterMove(
        series,
        occurrence,
        movedTime(occurrence, WeekSlot(DateTime(2026, 10, 13))),
      );
      expect(time, isA<AllDayEvent>());
      expect((time as AllDayEvent).start, equals(DateTime(2026, 9, 8)));
    });
  });
}
