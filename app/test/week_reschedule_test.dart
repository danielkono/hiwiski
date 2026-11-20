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

    // Days counted as `20261102 - 20261030` made the event 72 days long.
    test('an all-day event over a month end stays as long', () {
      final moved = movedTime(
        allDay(DateTime(2026, 10, 30), DateTime(2026, 11, 2)),
        WeekSlot(DateTime(2026, 10, 27)),
      );
      expect(moved.start, equals(DateTime(2026, 10, 27)));
      expect(moved.end, equals(DateTime(2026, 10, 30)));
    });

    test('a timed event over several days moves by one day into November', () {
      final moved = movedTime(
        timed(DateTime(2026, 10, 31, 18), DateTime(2026, 11, 2, 10)),
        WeekSlot(DateTime(2026, 11, 1)),
      );
      expect(moved.start, equals(DateTime(2026, 11, 1, 18)));
      expect(moved.end, equals(DateTime(2026, 11, 3, 10)));
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

  group('seriesAfterMove', () {
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
      final time = seriesAfterMove(
        series,
        occurrence,
        movedTime(occurrence, WeekSlot(DateTime(2026, 10, 14), 14 * 60)),
      ).time;
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
      final time = seriesAfterMove(
        series,
        occurrence,
        movedTime(occurrence, WeekSlot(DateTime(2026, 10, 13))),
      ).time;
      expect(time, isA<AllDayEvent>());
      expect((time as AllDayEvent).start, equals(DateTime(2026, 9, 8)));
    });

    test('a move into the next month moves the series by one day', () {
      final series = event(
        rrule: 'FREQ=WEEKLY',
        localStart: '2026-09-05T10:00:00',
      );
      // Saturday 31 October, moved to Sunday 1 November.
      final occurrence = timed(
        DateTime(2026, 10, 31, 10),
        DateTime(2026, 10, 31, 11),
        of: series,
      );
      final time = seriesAfterMove(
        series,
        occurrence,
        movedTime(occurrence, WeekSlot(DateTime(2026, 11, 1), 10 * 60)),
      ).time;
      expect((time as RecurringEvent).start, equals(DateTime(2026, 9, 6, 10)));
    });

    test('an occurrence moved off its day and dropped back there leaves the '
        'series where it is', () {
      final series = event(
        rrule: 'FREQ=WEEKLY',
        localStart: '2026-10-05T09:00:00',
      );
      // Monday 12 October, on Tuesday by an exception of the series.
      final occurrence = Occurrence(
        event: series,
        start: DateTime(2026, 10, 13, 9),
        end: DateTime(2026, 10, 13, 10),
        allDay: false,
        originalStart: DateTime(2026, 10, 12, 9),
      );
      final time = seriesAfterMove(
        series,
        occurrence,
        movedTime(occurrence, WeekSlot(DateTime(2026, 10, 12), 9 * 60)),
      ).time;
      expect((time as RecurringEvent).start, equals(DateTime(2026, 10, 5, 9)));
    });

    test('a series on Thursdays moved to a Friday starts on a Friday', () {
      final series = event(
        rrule: 'FREQ=WEEKLY;INTERVAL=2;BYDAY=TH',
        localStart: '2026-11-05T14:00:00',
      );
      final occurrence = timed(
        DateTime(2026, 11, 19, 14),
        DateTime(2026, 11, 19, 14, 30),
        of: series,
      );
      final move = seriesAfterMove(
        series,
        occurrence,
        movedTime(occurrence, WeekSlot(DateTime(2026, 11, 20), 14 * 60)),
      );
      expect(move.rrule, equals('FREQ=WEEKLY;INTERVAL=2;BYDAY=FR'));
      expect(
        (move.time as RecurringEvent).start,
        equals(DateTime(2026, 11, 6, 14)),
      );
      expect(move.cancelled, isEmpty);
    });

    test('a weekday moved before the start cancels what the first week '
        'never had', () {
      // From Thursday 5 November: Thursday 5 and Friday 6 in the first week.
      final series = event(
        rrule: 'FREQ=WEEKLY;BYDAY=TU,TH,FR;COUNT=20',
        localStart: '2026-11-05T09:00:00',
      );
      // Friday 13 November, moved to Monday 9 November.
      final occurrence = timed(
        DateTime(2026, 11, 13, 9),
        DateTime(2026, 11, 13, 10),
        of: series,
      );
      final move = seriesAfterMove(
        series,
        occurrence,
        movedTime(occurrence, WeekSlot(DateTime(2026, 11, 9), 9 * 60)),
      );
      // Friday 6 became Monday 2 — the series starts there; Tuesday 3 was never
      // one of its days. It still counts towards the 20.
      expect(
        (move.time as RecurringEvent).start,
        equals(DateTime(2026, 11, 2, 9)),
      );
      expect(move.cancelled, equals([DateTime(2026, 11, 3, 9)]));
      expect(move.rrule, equals('FREQ=WEEKLY;BYDAY=MO,TU,TH;COUNT=21'));
    });
  });

  group('ruleAfterMove', () {
    String? after(String rrule, DateTime original, DateTime target) =>
        ruleAfterMove(rrule, original: original, target: target);

    test('only the dragged weekday moves', () {
      // Monday 12 October to Tuesday.
      expect(
        after(
          'FREQ=WEEKLY;BYDAY=MO,WE',
          DateTime(2026, 10, 12, 9),
          DateTime(2026, 10, 13, 9),
        ),
        equals('FREQ=WEEKLY;BYDAY=TU,WE'),
      );
    });

    test('onto a weekday the series already has, the two become one', () {
      expect(
        after(
          'FREQ=WEEKLY;BYDAY=MO,WE',
          DateTime(2026, 10, 12, 9),
          DateTime(2026, 10, 14, 9),
        ),
        equals('FREQ=WEEKLY;BYDAY=WE'),
      );
    });

    test('the rest of the rule stays as it was', () {
      expect(
        after(
          'FREQ=WEEKLY;INTERVAL=2;BYDAY=TH;COUNT=10',
          DateTime(2026, 11, 19, 14),
          DateTime(2026, 11, 20, 14),
        ),
        equals('FREQ=WEEKLY;INTERVAL=2;BYDAY=FR;COUNT=10'),
      );
    });

    test('a move on the same day keeps the rule', () {
      const rule = 'FREQ=MONTHLY;BYDAY=-1TU';
      expect(
        after(rule, DateTime(2026, 11, 24, 9), DateTime(2026, 11, 24, 15)),
        equals(rule),
      );
    });

    test('a rule that repeats by its start keeps it', () {
      for (final rule in ['FREQ=WEEKLY', 'FREQ=MONTHLY', 'FREQ=YEARLY']) {
        expect(
          after(rule, DateTime(2026, 10, 12, 9), DateTime(2026, 10, 13, 9)),
          equals(rule),
        );
      }
    });

    test('a rule the editor does not understand is not rewritten', () {
      const rule = 'FREQ=WEEKLY;BYDAY=MO,WE;WKST=SU';
      expect(
        after(rule, DateTime(2026, 10, 12, 9), DateTime(2026, 10, 13, 9)),
        equals(rule),
      );
    });

    test('the nth weekday of a month becomes the target one', () {
      // Tuesday 10 November is the second; Wednesday 11 the second too.
      expect(
        after(
          'FREQ=MONTHLY;BYDAY=2TU',
          DateTime(2026, 11, 10, 9),
          DateTime(2026, 11, 11, 9),
        ),
        equals('FREQ=MONTHLY;BYDAY=2WE'),
      );
    });

    test('the last weekday stays the last where the target is', () {
      // Tuesday 24 November is the last; Wednesday 25 is, Monday 23 is not.
      expect(
        after(
          'FREQ=MONTHLY;BYDAY=-1TU',
          DateTime(2026, 11, 24, 9),
          DateTime(2026, 11, 25, 9),
        ),
        equals('FREQ=MONTHLY;BYDAY=-1WE'),
      );
      expect(
        after(
          'FREQ=MONTHLY;BYDAY=-1TU',
          DateTime(2026, 11, 24, 9),
          DateTime(2026, 11, 23, 9),
        ),
        equals('FREQ=MONTHLY;BYDAY=4MO'),
      );
    });
  });
}
