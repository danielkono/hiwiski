import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/domain/calendar/event_draft.dart';
import 'package:hiwiski/domain/calendar/occurrence.dart';
import 'package:hiwiski/domain/calendar/reschedule.dart';
import 'package:hiwiski/domain/common/calendar_days.dart';
import 'package:hiwiski/features/calendar/event_sheet/event_sheet_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **A new date for an occurrence in the editor moves its series as a drop in the
/// week view does.** The start moved and the rule did not: a Thursday series moved
/// to a Friday kept `BYDAY=TH`, and the occurrence that was edited was gone.
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
    container.listen(eventSheetViewModelProvider, (_, _) {});
    calendarId = await container
        .read(calendarRepositoryProvider)
        .createCalendar(name: 'Family', colorToken: ColorTokens.blue);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<List<DateTime>> startsIn(DateTime from, DateTime to) async {
    final events = await container
        .read(calendarRepositoryProvider)
        .watchEvents()
        .first;
    return [
      for (final event in events)
        for (final occurrence in const EventExpander().expand(event, from, to))
          occurrence.start,
    ]..sort();
  }

  /// Opens the occurrence at [opened] of a series from [first], sets its start to
  /// [to] — the rule as the form shows it then — and saves as far as [scope].
  Future<void> redate(
    String rrule,
    DateTime first,
    DateTime opened,
    DateTime to, {
    required SeriesScope scope,
  }) async {
    final calendars = container.read(calendarRepositoryProvider);
    final id = await calendars.createEvent(
      calendarId: calendarId,
      draft: EventDraft(
        title: 'Football',
        rrule: rrule,
        time: RecurringEvent(first, first.add(const Duration(hours: 1))),
      ),
    );
    final event = (await calendars.watchEvent(id).first)!;
    final occurrence = const EventExpander()
        .expand(event, opened, addDays(opened, 1))
        .singleWhere((item) => item.start == opened);
    final draft = EventDraft(
      title: 'Football',
      rrule: ruleAfterMove(rrule, original: opened, target: to),
      time: RecurringEvent(to, to.add(const Duration(hours: 1))),
    );
    await container
        .read(eventSheetViewModelProvider.notifier)
        .edit(
          event,
          calendarId: calendarId,
          defaultCalendarName: 'Family',
          occurrence: occurrence,
          series: draft,
          draft: draft,
          scope: scope,
        );
  }

  test('the whole series: every second Thursday becomes every second '
      'Friday', () async {
    await redate(
      'FREQ=WEEKLY;INTERVAL=2;BYDAY=TH',
      DateTime(2026, 11, 5, 14),
      DateTime(2026, 11, 19, 14),
      DateTime(2026, 11, 20, 14),
      scope: .wholeSeries,
    );

    expect(
      await startsIn(DateTime(2026, 11, 2), DateTime(2026, 12, 7)),
      equals([
        DateTime(2026, 11, 6, 14),
        DateTime(2026, 11, 20, 14),
        DateTime(2026, 12, 4, 14),
      ]),
    );
  });

  test('this and all following, moved before a weekday it kept: that day '
      'shows once', () async {
    // Friday 16 to Tuesday 13 — Wednesday 14 still belongs to the old part.
    await redate(
      'FREQ=WEEKLY;BYDAY=MO,WE,FR',
      DateTime(2026, 10, 5, 9),
      DateTime(2026, 10, 16, 9),
      DateTime(2026, 10, 13, 9),
      scope: .thisAndFollowing,
    );

    expect(
      await startsIn(DateTime(2026, 10, 12), DateTime(2026, 10, 26)),
      equals([
        DateTime(2026, 10, 12, 9),
        DateTime(2026, 10, 13, 9),
        DateTime(2026, 10, 14, 9),
        DateTime(2026, 10, 19, 9),
        DateTime(2026, 10, 20, 9),
        DateTime(2026, 10, 21, 9),
      ]),
    );
  });

  test('this and all following: the second Tuesday of the month becomes the '
      'second Wednesday', () async {
    await redate(
      'FREQ=MONTHLY;BYDAY=2TU',
      DateTime(2026, 10, 13, 9),
      DateTime(2026, 11, 10, 9),
      DateTime(2026, 11, 11, 9),
      scope: .thisAndFollowing,
    );

    expect(
      await startsIn(DateTime(2026, 10, 1), DateTime(2027, 1, 1)),
      equals([
        DateTime(2026, 10, 13, 9),
        DateTime(2026, 11, 11, 9),
        DateTime(2026, 12, 9, 9),
      ]),
    );
  });
}
