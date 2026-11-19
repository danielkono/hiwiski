import 'package:hiwiski/domain/calendar/occurrence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:hiwiski/domain/calendar/calendar_items.dart';

/// Expanding an event into a window — three time forms, three paths.
///
/// Agreement with the server is checked in `recurrence_golden_test.dart` against
/// `golden/recurrence.json`. This is about what sits on top of that: all-day events,
/// multi-day events and the **exceptions** of a series.
void main() {
  setUpAll(tz_data.initializeTimeZones);

  CalendarEvent event({
    String timeForm = 'TIMED',
    DateTime? startsAt,
    DateTime? endsAt,
    DateTime? startDate,
    DateTime? endDate,
    String? localStart,
    String? localEnd,
    String? rrule,
    String exceptions = '{}',
    DateTime? deletedAt,
  }) => .new(
    id: 'e1',
    ownerId: 'anna',
    version: 1,
    tags: '',
    calendarId: 'c1',
    title: 'Test',
    timeForm: timeForm,
    startsAt: startsAt,
    endsAt: endsAt,
    startDate: startDate,
    endDate: endDate,
    localStart: localStart,
    localEnd: localEnd,
    timeZone: 'Europe/Berlin',
    rrule: rrule,
    exceptions: exceptions,
    attendees: '',
    deletedAt: deletedAt,
  );

  const expander = EventExpander();

  test('sorts by day first, then all-day events first', () {
    // On the first run the holiday week starting Friday stood before today's event in
    // the start widget: "all-day first" applied across all days instead of per day.
    final today = expander
        .expand(
          event(
            startsAt: DateTime.utc(2026, 9, 30, 13),
            endsAt: DateTime.utc(2026, 9, 30, 15),
          ),
          DateTime(2026, 9),
          DateTime(2026, 11),
        )
        .single;
    final holidays = expander
        .expand(
          event(
            timeForm: 'ALL_DAY',
            startDate: DateTime(2026, 10, 2),
            endDate: DateTime(2026, 10, 9),
          ),
          DateTime(2026, 9),
          DateTime(2026, 11),
        )
        .single;
    final fridayMorning = expander
        .expand(
          event(
            startsAt: DateTime.utc(2026, 10, 2, 6),
            endsAt: DateTime.utc(2026, 10, 2, 7),
          ),
          DateTime(2026, 9),
          DateTime(2026, 11),
        )
        .single;

    expect(
      [holidays, fridayMorning, today]..sort(),
      equals([today, holidays, fridayMorning]),
    );
  });

  group('all-day', () {
    test('multi-day is one occurrence, not twelve', () {
      // "Summer holidays 29.09.–10.10." — **once with from–to, not again on every
      // day**.
      final rows = expander.expand(
        event(
          timeForm: 'ALL_DAY',
          startDate: DateTime(2026, 9, 29),
          endDate: DateTime(2026, 10, 10),
        ),
        DateTime(2026, 9),
        DateTime(2026, 11),
      );

      expect(rows, hasLength(1));
      expect(rows.single.isMultiDay, isTrue);
      expect(rows.single.isPinned, isTrue);
      expect(rows.single.touches(DateTime(2026, 10, 5)), isTrue);
      expect(rows.single.touches(DateTime(2026, 10, 11)), isFalse);
    });

    test('the whole end day still counts', () {
      // A window that starts on the end day must still see the event — otherwise
      // "today is the last day of the holidays" would vanish on the morning of that day.
      final rows = expander.expand(
        event(
          timeForm: 'ALL_DAY',
          startDate: DateTime(2026, 9, 29),
          endDate: DateTime(2026, 10, 10),
        ),
        DateTime(2026, 10, 10),
        DateTime(2026, 10, 12),
      );
      expect(rows, hasLength(1));
    });

    // An all-day event with a repeat rule showed only once, on its first day — and
    // without an original start, edit and delete never asked "only this one?".
    test('a yearly birthday comes back every year', () {
      final rows = expander.expand(
        event(
          timeForm: 'ALL_DAY',
          startDate: DateTime(2020, 3, 14),
          endDate: DateTime(2020, 3, 14),
          rrule: 'FREQ=YEARLY',
        ),
        DateTime(2026),
        DateTime(2028),
      );
      expect(
        rows.map((row) => row.start),
        equals([DateTime(2026, 3, 14), DateTime(2027, 3, 14)]),
      );
      expect(rows.every((row) => row.allDay), isTrue);
      expect(rows.first.originalStart, equals(DateTime(2026, 3, 14)));
    });

    test('a multi-day series reaches into the window it runs in', () {
      final rows = expander.expand(
        event(
          timeForm: 'ALL_DAY',
          startDate: DateTime(2026, 10, 2),
          endDate: DateTime(2026, 10, 4),
          rrule: 'FREQ=WEEKLY',
        ),
        DateTime(2026, 10, 11),
        DateTime(2026, 10, 12),
      );
      expect(rows.single.start, equals(DateTime(2026, 10, 9)));
      expect(rows.single.end, equals(DateTime(2026, 10, 11)));
    });

    test('a cancelled day of an all-day series drops out', () {
      final rows = expander.expand(
        event(
          timeForm: 'ALL_DAY',
          startDate: DateTime(2026, 10, 5),
          endDate: DateTime(2026, 10, 5),
          rrule: 'FREQ=WEEKLY;COUNT=3',
          exceptions: '{"2026-10-12T00:00": {"cancelled": true}}',
        ),
        DateTime(2026, 10),
        DateTime(2026, 11),
      );
      expect(
        rows.map((row) => row.start),
        equals([DateTime(2026, 10, 5), DateTime(2026, 10, 19)]),
      );
    });
  });

  group('exceptions of a series', () {
    test('one moved into the window from outside it is there', () {
      // Monday 19 October moved to Friday 16: the week of 12–18 October has to
      // show it, though its original start lies outside.
      final rows = expander.expand(
        event(
          timeForm: 'RECURRING',
          localStart: '2026-10-05T08:00',
          localEnd: '2026-10-05T09:00',
          rrule: 'FREQ=WEEKLY;BYDAY=MO',
          exceptions: '{"2026-10-19T08:00": {"start": "2026-10-16T14:00", "end": "2026-10-16T15:00"}}',
        ),
        DateTime(2026, 10, 13),
        DateTime(2026, 10, 19),
      );
      expect(rows.single.start, equals(DateTime(2026, 10, 16, 14)));
      expect(rows.single.originalStart, equals(DateTime(2026, 10, 19, 8)));
      expect(rows.single.moved, isTrue);
    });

    test('a stale key that is no occurrence of the rule stays out', () {
      final rows = expander.expand(
        event(
          timeForm: 'RECURRING',
          localStart: '2026-10-05T08:00',
          localEnd: '2026-10-05T09:00',
          rrule: 'FREQ=WEEKLY;BYDAY=MO',
          exceptions: '{"2026-10-20T08:00": {"start": "2026-10-16T14:00", "end": "2026-10-16T15:00"}}',
        ),
        DateTime(2026, 10, 13),
        DateTime(2026, 10, 19),
      );
      expect(rows, isEmpty);
    });

    final weekly = event(
      timeForm: 'RECURRING',
      localStart: '2026-10-05T08:00',
      localEnd: '2026-10-05T09:00',
      rrule: 'RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=4',
    );

    test('without an exception all four are there', () {
      final rows = expander.expand(
        weekly,
        DateTime(2026, 10),
        DateTime(2026, 12),
      );
      expect(rows.map((row) => row.start.day), equals([5, 12, 19, 26]));
    });

    test('a cancelled one drops out', () {
      final rows = expander.expand(
        event(
          timeForm: 'RECURRING',
          localStart: '2026-10-05T08:00',
          localEnd: '2026-10-05T09:00',
          rrule: 'RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=4',
          exceptions: '{"2026-10-12T08:00": {"cancelled": true}}',
        ),
        DateTime(2026, 10),
        DateTime(2026, 12),
      );
      expect(rows.map((row) => row.start.day), equals([5, 19, 26]));
    });

    test('a moved one is at its new place, with the old key', () {
      final rows = expander.expand(
        event(
          timeForm: 'RECURRING',
          localStart: '2026-10-05T08:00',
          localEnd: '2026-10-05T09:00',
          rrule: 'RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=4',
          exceptions: '{"2026-10-19T08:00": {"start": "2026-10-20T14:00", "end": "2026-10-20T15:00"}}',
        ),
        DateTime(2026, 10),
        DateTime(2026, 12),
      );

      final moved = rows.firstWhere((row) => row.moved);
      expect(moved.start, equals(DateTime(2026, 10, 20, 14)));
      expect(moved.end, equals(DateTime(2026, 10, 20, 15)));
      // The key stays the **original** start — otherwise the next
      // change would not find its own exception again.
      expect(
        EventExpander.formatKey(moved.originalStart!),
        equals('2026-10-19T08:00'),
      );
    });

    test('a broken column does not cost the calendar', () {
      final rows = expander.expand(
        event(
          timeForm: 'RECURRING',
          localStart: '2026-10-05T08:00',
          localEnd: '2026-10-05T09:00',
          rrule: 'RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=2',
          exceptions: 'not JSON',
        ),
        DateTime(2026, 10),
        DateTime(2026, 12),
      );
      expect(rows, hasLength(2));
    });
  });

  test('a series keeps its time of day across the clock change', () {
    // "every Monday 8:00" stays 8:00; computed in UTC it would shift to 9:00.
    //25 October 2026 is the switch to winter time.
    final rows = expander.expand(
      event(
        timeForm: 'RECURRING',
        localStart: '2026-10-19T08:00',
        localEnd: '2026-10-19T09:00',
        rrule: 'RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=3',
      ),
      DateTime(2026, 10),
      DateTime(2026, 12),
    );

    expect(rows.map((row) => row.start.hour), everyElement(8));
    expect(rows.map((row) => row.end.hour), everyElement(9));
  });

  test('a deleted event does not expand', () {
    final rows = expander.expand(
      event(
        startsAt: DateTime.utc(2026, 10, 5, 6),
        deletedAt: DateTime(2026, 10),
      ),
      DateTime(2026, 10),
      DateTime(2026, 11),
    );
    expect(rows, isEmpty);
  });

  // "This and all following" from the first occurrence left a ghost series that
  // expanded to nothing — it is the whole series.
  group('nothing before', () {
    final weekly = event(
      timeForm: 'RECURRING',
      localStart: '2026-10-05T08:00',
      localEnd: '2026-10-05T09:00',
      rrule: 'FREQ=WEEKLY',
      exceptions: '{"2026-10-05T08:00": {"cancelled": true}}',
    );

    test('from the first occurrence, nothing comes before', () {
      expect(nothingBefore(weekly, DateTime(2026, 10, 5, 8)), isTrue);
    });

    test('a cancelled first occurrence does not count', () {
      expect(nothingBefore(weekly, DateTime(2026, 10, 12, 8)), isTrue);
    });

    test('from a later one, the earlier ones stay', () {
      expect(nothingBefore(weekly, DateTime(2026, 10, 19, 8)), isFalse);
    });
  });

  // Opened without a date and with nothing nearby, a weekly series showed the
  // occurrence a year ahead — and edit and delete acted on it.
  group('the occurrence one means', () {
    final weekly = event(
      timeForm: 'RECURRING',
      localStart: '2026-01-05T08:00',
      localEnd: '2026-01-05T09:00',
      rrule: 'FREQ=WEEKLY',
    );

    test('without one nearby, the next', () {
      expect(
        occurrenceNear(weekly, at: DateTime(2026, 10, 8, 12))?.start,
        equals(DateTime(2026, 10, 12, 8)),
      );
    });

    test('a series that has ended, its last', () {
      final ended = event(
        timeForm: 'RECURRING',
        localStart: '2026-01-05T08:00',
        localEnd: '2026-01-05T09:00',
        rrule: 'FREQ=WEEKLY;COUNT=3',
      );
      expect(
        occurrenceNear(ended, at: DateTime(2026, 10, 8, 12))?.start,
        equals(DateTime(2026, 1, 19, 8)),
      );
    });
  });

  group('occurrences by day', () {
    Occurrence span(DateTime start, DateTime end, {bool allDay = true}) =>
        .new(event: event(), start: start, end: end, allDay: allDay);

    test('a span is under every day it covers, clipped to the window', () {
      // The holidays reach back into the previous month and on past the grid.
      final holidays = span(DateTime(2026, 9, 28), DateTime(2026, 10, 3));
      final byDay = occurrencesByDay(
        [holidays],
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 2),
      );
      expect(byDay.keys, equals([20261001, 20261002]));
      expect(byDay[20261001], equals([holidays]));
    });

    test('each day keeps the order it was given', () {
      final evening = span(
        DateTime(2026, 10, 10, 19),
        DateTime(2026, 10, 10, 20),
        allDay: false,
      );
      final allDay = span(DateTime(2026, 10, 10), DateTime(2026, 10, 10));
      final sorted = [evening, allDay]..sort();
      final byDay = occurrencesByDay(
        sorted,
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 31),
      );
      expect(byDay[20261010], equals([allDay, evening]));
      expect(evening.touches(DateTime(2026, 10, 10, 23, 59)), isTrue);
      expect(evening.touches(DateTime(2026, 10, 11)), isFalse);
    });
  });
}
