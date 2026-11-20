import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/domain/common/change.dart';
import 'package:hiwiski/core/platform/reminder_scheduler.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/domain/calendar/calendar_reminders.dart';
import 'package:hiwiski/domain/calendar/event_draft.dart';
import 'package:hiwiski/domain/common/calendar_days.dart';
import 'package:hiwiski/data/calendar/reminder_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **A calendar's default reminder applies to every event without one of its own —
/// existing ones too**.
void main() {
  group('the rule', () {
    test('its own wins, otherwise the calendar\'s', () {
      expect(effectiveReminder(15, 60), equals(15));
      expect(effectiveReminder(null, 60), equals(60));
      expect(effectiveReminder(null, null), isNull);
    });

    test('"none" on the event stays silent despite the default', () {
      expect(effectiveReminder(ReminderMinutes.none, 60), isNull);
    });
  });

  group('the text says when', () {
    final shownAt = DateTime(2026, 10, 25, 9);

    String when(DateTime start, DateTime end, {bool allDay = false}) =>
        reminderWhen(
          (start: start, end: end, allDay: allDay),
          shownAt: shownAt,
          words: _words,
        );

    test('today, with start and end', () {
      expect(
        when(DateTime(2026, 10, 25, 10), DateTime(2026, 10, 25, 11, 30)),
        equals('today, 10:00–11:30'),
      );
    });

    test('tomorrow — not a bare time that reads as today', () {
      expect(
        when(DateTime(2026, 10, 26, 8, 5), DateTime(2026, 10, 26, 9)),
        equals('tomorrow, 08:05–09:00'),
      );
    });

    test('a day further off by its date', () {
      expect(
        when(DateTime(2026, 10, 28, 18), DateTime(2026, 10, 28, 19)),
        equals('day, 18:00–19:00'),
      );
    });

    test('ending on another day: the start alone', () {
      expect(
        when(DateTime(2026, 10, 25, 22), DateTime(2026, 10, 26, 2)),
        equals('today, 22:00'),
      );
    });

    test('all day instead of 00:00', () {
      expect(
        when(DateTime(2026, 10, 26), DateTime(2026, 10, 26), allDay: true),
        equals('tomorrow · all day'),
      );
    });
  });

  group('scheduling', () {
    late HiwiskiDatabase db;
    late ProviderContainer container;
    late _Scheduler scheduler;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final settings = await LocalSettings.open();
      db = HiwiskiDatabase(NativeDatabase.memory());
      scheduler = _Scheduler();
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          localSettingsProvider.overrideWithValue(settings),
          deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test(
      'an existing event takes the default set later on the calendar',
      () async {
        final calendars = container.read(calendarRepositoryProvider);
        final calendarId = await calendars.createCalendar(
          name: 'Family',
          colorToken: ColorTokens.blue,
        );
        final soon = addDays(DateTime.now(), 2);
        final start = DateTime(soon.year, soon.month, soon.day, 10);
        await calendars.createEvent(
          calendarId: calendarId,
          draft: EventDraft(
            title: 'Dentist',
            time: TimedEvent(start, start.add(const Duration(hours: 1))),
          ),
        );
        await calendars.createEvent(
          calendarId: calendarId,
          draft: EventDraft(
            title: 'Quiet',
            time: TimedEvent(start, start.add(const Duration(hours: 1))),
            reminderMinutes: ReminderMinutes.none,
          ),
        );
        final reminders = ReminderRepository(
          db: db,
          scheduler: scheduler,
          timeZone: 'Europe/Berlin',
          words: () => _words,
        );

        await reminders.rescheduleAll();
        expect(scheduler.scheduled, isEmpty);

        final calendar =
            (await container
                    .read(calendarRepositoryProvider)
                    .watchCalendars()
                    .first)
                .single;
        await calendars.updateCalendar(
          calendar,
          defaultReminderMinutes: const Change(30),
        );
        await reminders.rescheduleAll();

        expect(scheduler.scheduled.map((r) => r.title), equals(['Dentist']));
        // Two days off now, but the reminder rings on the day itself.
        expect(scheduler.scheduled.single.body, equals('today, 10:00–11:00'));

        // Tapped, it leads to its event at this occurrence.
        final dentist = (await container
            .read(calendarRepositoryProvider)
            .watchEvent(
              (await db.select(db.events).get())
                  .firstWhere((row) => row.title == 'Dentist')
                  .id,
            )
            .first)!;
        final tapped = reminders.opened.first;
        scheduler.taps.add(scheduler.scheduled.single.payload);
        expect(await tapped, equals((eventId: dentist.id, start: start)));

        scheduler.launch = scheduler.scheduled.single.payload;
        expect(
          await reminders.takeLaunchTarget(),
          equals((eventId: dentist.id, start: start)),
        );
        expect(
          scheduler.scheduled.single.when,
          equals(start.subtract(const Duration(minutes: 30))),
        );
      },
    );

    test('the day is told from when the reminder rings, not from when it '
        'is scheduled', () async {
      final calendars = container.read(calendarRepositoryProvider);
      final calendarId = await calendars.createCalendar(
        name: 'Family',
        colorToken: ColorTokens.blue,
      );
      final soon = addDays(DateTime.now(), 2);
      final start = DateTime(soon.year, soon.month, soon.day, 10);
      for (final (title, minutes) in [
        ('Shortly before', 30),
        ('A day ahead', 24 * 60),
      ]) {
        await calendars.createEvent(
          calendarId: calendarId,
          draft: EventDraft(
            title: title,
            time: TimedEvent(start, start.add(const Duration(hours: 1))),
            reminderMinutes: minutes,
          ),
        );
      }
      final reminders = ReminderRepository(
        db: db,
        scheduler: scheduler,
        timeZone: 'Europe/Berlin',
        words: () => _words,
      );

      await reminders.rescheduleAll();

      expect(
        {for (final r in scheduler.scheduled) r.title: r.body},
        equals({
          'A day ahead': 'tomorrow, 10:00–11:00',
          'Shortly before': 'today, 10:00–11:00',
        }),
      );
    });

    test('a run without the app schedules from the database and asks '
        'nobody', () async {
      final calendars = container.read(calendarRepositoryProvider);
      final calendarId = await calendars.createCalendar(
        name: 'Family',
        colorToken: ColorTokens.blue,
      );
      final soon = addDays(DateTime.now(), 2);
      final start = DateTime(soon.year, soon.month, soon.day, 10);
      await calendars.createEvent(
        calendarId: calendarId,
        draft: EventDraft(
          title: 'Dentist',
          time: TimedEvent(start, start.add(const Duration(hours: 1))),
          reminderMinutes: 30,
        ),
      );
      final reminders = ReminderRepository(
        db: db,
        scheduler: scheduler,
        timeZone: 'Europe/Berlin',
        words: () => _words,
      );

      await reminders.rescheduleOnce();

      expect(scheduler.asked, equals([false]));
      expect(scheduler.scheduled.map((r) => r.title), equals(['Dentist']));

      // Nobody watches the tables there: a later change is the next run's.
      await calendars.createEvent(
        calendarId: calendarId,
        draft: EventDraft(
          title: 'School',
          time: TimedEvent(start, start.add(const Duration(hours: 1))),
          reminderMinutes: 30,
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(scheduler.scheduled.map((r) => r.title), equals(['Dentist']));
    });
  });
}

const _words = ReminderWords(
  today: 'today',
  tomorrow: 'tomorrow',
  allDay: 'all day',
  date: _date,
);

String _date(DateTime day) => 'day';

class _Scheduler implements ReminderScheduler {
  List<PendingReminder> scheduled = const [];

  @override
  bool get supported => true;

  /// Whether each `initialize` was allowed to ask for the permission.
  final asked = <bool>[];

  @override
  Future<void> initialize(String timeZone, {bool askPermission = true}) async =>
      asked.add(askPermission);

  @override
  Future<void> replaceAll(List<PendingReminder> reminders) async =>
      scheduled = reminders;

  final taps = StreamController<String>.broadcast();
  String? launch;

  @override
  Stream<String> get opened => taps.stream;

  @override
  Future<String?> takeLaunchPayload() async => launch;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
