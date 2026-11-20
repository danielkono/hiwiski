import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/domain/calendar/calendar_items.dart';
import 'package:hiwiski/domain/calendar/event_draft.dart';
import 'package:hiwiski/domain/calendar/occurrence.dart';
import 'package:hiwiski/domain/calendar/reschedule.dart';
import 'package:hiwiski/features/calendar/overview/calendar_overview_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **An event dropped in the week view is written where it landed** — a single one
/// moved, a series as far as the member chose.
void main() {
  late HiwiskiDatabase db;
  late ProviderContainer container;
  late String calendarId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = HiwiskiDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(await LocalSettings.open()),
        deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
      ],
    );
    container.listen(calendarOverviewViewModelProvider, (_, _) {});
    calendarId = await container
        .read(calendarRepositoryProvider)
        .createCalendar(name: 'Family', colorToken: ColorTokens.blue);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<CalendarEvent> create(EventDraft draft) async {
    final calendars = container.read(calendarRepositoryProvider);
    final id = await calendars.createEvent(
      calendarId: calendarId,
      draft: draft,
    );
    return (await calendars.watchEvent(id).first)!;
  }

  Future<List<Occurrence>> occurrencesOn(DateTime day) async {
    final events = await container
        .read(calendarRepositoryProvider)
        .watchEvents()
        .first;
    return [
      for (final event in events)
        ...const EventExpander().expand(
          event,
          day,
          DateTime(day.year, day.month, day.day + 1),
        ),
    ]..sort();
  }

  CalendarOverviewViewModel viewModel() =>
      container.read(calendarOverviewViewModelProvider.notifier);

  test('a timed event moves to the slot and keeps its length', () async {
    await create(
      EventDraft(
        title: 'Dentist',
        time: TimedEvent(
          DateTime(2026, 10, 12, 8),
          DateTime(2026, 10, 12, 9, 30),
        ),
      ),
    );
    final occurrence = (await occurrencesOn(DateTime(2026, 10, 12))).single;

    await viewModel().moveOccurrence(
      occurrence,
      WeekSlot(DateTime(2026, 10, 13), 14 * 60 + 15),
    );

    final moved = (await occurrencesOn(DateTime(2026, 10, 13))).single;
    expect(moved.start, equals(DateTime(2026, 10, 13, 14, 15)));
    expect(moved.end, equals(DateTime(2026, 10, 13, 15, 45)));
    expect(await occurrencesOn(DateTime(2026, 10, 12)), isEmpty);
  });

  test('a timed event dropped on the band becomes all-day', () async {
    await create(
      EventDraft(
        title: 'Dentist',
        time: TimedEvent(DateTime(2026, 10, 12, 8), DateTime(2026, 10, 12, 9)),
      ),
    );
    final occurrence = (await occurrencesOn(DateTime(2026, 10, 12))).single;

    await viewModel().moveOccurrence(
      occurrence,
      WeekSlot(DateTime(2026, 10, 14)),
    );

    final moved = (await occurrencesOn(DateTime(2026, 10, 14))).single;
    expect(moved.allDay, isTrue);
    expect(moved.event.timeForm, equals(TimeForms.allDay));
  });

  test('an all-day event dropped into the hours lasts 30 minutes', () async {
    await create(
      EventDraft(
        title: 'Holiday',
        time: AllDayEvent(DateTime(2026, 10, 12), DateTime(2026, 10, 12)),
      ),
    );
    final occurrence = (await occurrencesOn(DateTime(2026, 10, 12))).single;

    await viewModel().moveOccurrence(
      occurrence,
      WeekSlot(DateTime(2026, 10, 12), 9 * 60),
    );

    final moved = (await occurrencesOn(DateTime(2026, 10, 12))).single;
    expect(moved.allDay, isFalse);
    expect(moved.start, equals(DateTime(2026, 10, 12, 9)));
    expect(moved.end, equals(DateTime(2026, 10, 12, 9, 30)));
  });

  group('a series', () {
    Future<Occurrence> weeklyOn12th() async {
      await create(
        EventDraft(
          title: 'Swimming',
          rrule: 'FREQ=WEEKLY',
          time: RecurringEvent(
            DateTime(2026, 10, 5, 17),
            DateTime(2026, 10, 5, 18),
          ),
        ),
      );
      return (await occurrencesOn(DateTime(2026, 10, 12))).single;
    }

    test('only this one: it leaves the series, the rest stays', () async {
      final occurrence = await weeklyOn12th();

      await viewModel().moveOccurrence(
        occurrence,
        WeekSlot(DateTime(2026, 10, 12), 19 * 60),
        scope: .onlyThis,
      );

      final moved = (await occurrencesOn(DateTime(2026, 10, 12))).single;
      expect(moved.start, equals(DateTime(2026, 10, 12, 19)));
      expect(moved.isSeries, isFalse);
      final next = (await occurrencesOn(DateTime(2026, 10, 19))).single;
      expect(next.start, equals(DateTime(2026, 10, 19, 17)));
    });

    test('the whole series moves with it', () async {
      final occurrence = await weeklyOn12th();

      await viewModel().moveOccurrence(
        occurrence,
        WeekSlot(DateTime(2026, 10, 13), 19 * 60),
      );

      expect(await occurrencesOn(DateTime(2026, 10, 12)), isEmpty);
      final first = (await occurrencesOn(DateTime(2026, 10, 6))).single;
      expect(first.start, equals(DateTime(2026, 10, 6, 19)));
      final later = (await occurrencesOn(DateTime(2026, 10, 20))).single;
      expect(later.start, equals(DateTime(2026, 10, 20, 19)));
    });
  });

  /// A weekly rule with named weekdays — what the editor writes for every weekly
  /// series. Only the dragged weekday moves; the start used to move without the
  /// rule, and the dropped event vanished from its week.
  group('a series on named weekdays', () {
    Future<List<DateTime>> startsIn(DateTime from, DateTime to) async {
      final events = await container
          .read(calendarRepositoryProvider)
          .watchEvents()
          .first;
      return [
        for (final event in events)
          for (final occurrence in const EventExpander().expand(
            event,
            from,
            to,
          ))
            occurrence.start,
      ]..sort();
    }

    Future<Occurrence> seriesOn(
      String rrule,
      DateTime first,
      DateTime occurrence,
    ) async {
      await create(
        EventDraft(
          title: 'Football',
          rrule: rrule,
          time: RecurringEvent(first, first.add(const Duration(hours: 1))),
        ),
      );
      return (await occurrencesOn(occurrence))
          .singleWhere((item) => item.start == occurrence);
    }

    Future<void> drop(
      Occurrence occurrence,
      DateTime at, {
      SeriesScope scope = .wholeSeries,
    }) => viewModel().moveOccurrence(
      occurrence,
      WeekSlot(at, at.hour * 60 + at.minute),
      scope: scope,
    );

    test(
      'every second Thursday, moved to a Friday, is on that Friday',
      () async {
        final occurrence = await seriesOn(
          'FREQ=WEEKLY;INTERVAL=2;BYDAY=TH',
          DateTime(2026, 11, 5, 14),
          DateTime(2026, 11, 19, 14),
        );

        await drop(occurrence, DateTime(2026, 11, 20, 14));

        expect(
          await startsIn(DateTime(2026, 11, 2), DateTime(2026, 12, 7)),
          equals([
            DateTime(2026, 11, 6, 14),
            DateTime(2026, 11, 20, 14),
            DateTime(2026, 12, 4, 14),
          ]),
        );
      },
    );

    test('the whole series: Monday and Wednesday become Tuesday and '
        'Wednesday', () async {
      final occurrence = await seriesOn(
        'FREQ=WEEKLY;BYDAY=MO,WE',
        DateTime(2026, 10, 5, 9),
        DateTime(2026, 10, 12, 9),
      );

      await drop(occurrence, DateTime(2026, 10, 13, 10));

      expect(
        await startsIn(DateTime(2026, 10, 5), DateTime(2026, 10, 19)),
        equals([
          DateTime(2026, 10, 6, 10),
          DateTime(2026, 10, 7, 10),
          DateTime(2026, 10, 13, 10),
          DateTime(2026, 10, 14, 10),
        ]),
      );
    });

    test(
      'this and all following: the weeks before stay as they were',
      () async {
        final occurrence = await seriesOn(
          'FREQ=WEEKLY;BYDAY=MO,WE',
          DateTime(2026, 10, 5, 9),
          DateTime(2026, 10, 12, 9),
        );

        await drop(
          occurrence,
          DateTime(2026, 10, 13, 10),
          scope: .thisAndFollowing,
        );

        expect(
          await startsIn(DateTime(2026, 10, 5), DateTime(2026, 10, 26)),
          equals([
            DateTime(2026, 10, 5, 9),
            DateTime(2026, 10, 7, 9),
            DateTime(2026, 10, 13, 10),
            DateTime(2026, 10, 14, 10),
            DateTime(2026, 10, 20, 10),
            DateTime(2026, 10, 21, 10),
          ]),
        );
      },
    );

    test('this and all following, moved before a weekday it kept: that day '
        'shows once', () async {
      final occurrence = await seriesOn(
        'FREQ=WEEKLY;BYDAY=MO,WE,FR',
        DateTime(2026, 10, 5, 9),
        DateTime(2026, 10, 16, 9),
      );

      // Friday 16 to Tuesday 13 — Wednesday 14 still belongs to the old part.
      await drop(
        occurrence,
        DateTime(2026, 10, 13, 10),
        scope: .thisAndFollowing,
      );

      expect(
        await startsIn(DateTime(2026, 10, 12), DateTime(2026, 10, 26)),
        equals([
          DateTime(2026, 10, 12, 9),
          DateTime(2026, 10, 13, 10),
          DateTime(2026, 10, 14, 9),
          DateTime(2026, 10, 19, 10),
          DateTime(2026, 10, 20, 10),
          DateTime(2026, 10, 21, 10),
        ]),
      );
    });

    test('the whole series, moved before its first day, gains no day it never '
        'had', () async {
      // From Thursday 5 November: Thursday 5 and Friday 6 in the first week.
      final occurrence = await seriesOn(
        'FREQ=WEEKLY;BYDAY=TU,TH,FR',
        DateTime(2026, 11, 5, 9),
        DateTime(2026, 11, 13, 9),
      );

      await drop(occurrence, DateTime(2026, 11, 9, 9));

      expect(
        await startsIn(DateTime(2026, 11, 2), DateTime(2026, 11, 16)),
        equals([
          DateTime(2026, 11, 2, 9),
          DateTime(2026, 11, 5, 9),
          DateTime(2026, 11, 9, 9),
          DateTime(2026, 11, 10, 9),
          DateTime(2026, 11, 12, 9),
        ]),
      );
    });

    test('a cancelled day stays cancelled on its own weekday', () async {
      await seriesOn(
        'FREQ=WEEKLY;BYDAY=MO,WE',
        DateTime(2026, 10, 5, 9),
        DateTime(2026, 10, 12, 9),
      );
      final calendars = container.read(calendarRepositoryProvider);
      Future<CalendarEvent> series() async =>
          (await calendars.watchEvents().first).single;
      await calendars.cancelOccurrence(
        await series(),
        DateTime(2026, 10, 21, 9),
      );
      await calendars.cancelOccurrence(
        await series(),
        DateTime(2026, 10, 26, 9),
      );
      // The occurrence as it is now, with the cancelled days on its series.
      final current = (await occurrencesOn(DateTime(2026, 10, 12))).single;

      await drop(current, DateTime(2026, 10, 13, 10), scope: .thisAndFollowing);

      // Wednesday 21 stays off; Monday 26 is off as Tuesday 27.
      expect(
        await startsIn(DateTime(2026, 10, 19), DateTime(2026, 11, 2)),
        equals([DateTime(2026, 10, 20, 10), DateTime(2026, 10, 28, 10)]),
      );
    });

    test('this and all following keeps the count a series has left', () async {
      final occurrence = await seriesOn(
        'FREQ=WEEKLY;BYDAY=MO,WE;COUNT=6',
        DateTime(2026, 10, 5, 9),
        DateTime(2026, 10, 12, 9),
      );

      await drop(
        occurrence,
        DateTime(2026, 10, 13, 10),
        scope: .thisAndFollowing,
      );

      expect(
        await startsIn(DateTime(2026, 10, 1), DateTime(2026, 12, 1)),
        equals([
          DateTime(2026, 10, 5, 9),
          DateTime(2026, 10, 7, 9),
          DateTime(2026, 10, 13, 10),
          DateTime(2026, 10, 14, 10),
          DateTime(2026, 10, 20, 10),
          DateTime(2026, 10, 21, 10),
        ]),
      );
    });
  });
}
