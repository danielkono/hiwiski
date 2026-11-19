import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/domain/calendar/calendar_items.dart';
import 'package:hiwiski/domain/calendar/event_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:hiwiski/app/repositories.dart';

/// **"This and all following" takes along what belongs to the rest.** The new part
/// restarted `COUNT` — a 10-times series split at the 6th ran 15 times — and left the
/// exceptions after the split behind, so a cancelled day came back.
void main() {
  setUpAll(tz_data.initializeTimeZones);

  test('a split keeps the count and carries the later exceptions', () async {
    SharedPreferences.setMockInitialValues({});
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(await LocalSettings.open()),
        deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
      ],
    );
    addTearDown(container.dispose);
    final calendar = container.read(calendarRepositoryProvider);
    final calendarId = await calendar.createCalendar(
      name: 'Family',
      colorToken: ColorTokens.blue,
    );
    const rule = 'FREQ=WEEKLY;COUNT=10';
    final id = await calendar.createEvent(
      calendarId: calendarId,
      draft: EventDraft(
        title: 'Swimming',
        rrule: rule,
        time: RecurringEvent(
          DateTime(2026, 9, 7, 17),
          DateTime(2026, 9, 7, 18),
        ),
      ),
    );
    Future<CalendarEvent> current() async {
      await Future<void>.delayed(Duration.zero);
      final CalendarEvent? event = await container
          .read(calendarRepositoryProvider)
          .watchEvent(id)
          .first;
      return event!;
    }

    // Before the split point and after it.
    await calendar.cancelOccurrence(await current(), DateTime(2026, 9, 14, 17));
    await calendar.cancelOccurrence(
      await current(),
      DateTime(2026, 10, 26, 17),
    );

    // At the 6th occurrence, one hour later from then on.
    final newId = await calendar.splitSeries(
      event: await current(),
      from: DateTime(2026, 10, 12, 17),
      calendarId: calendarId,
      draft: EventDraft(
        title: 'Swimming',
        rrule: rule,
        time: RecurringEvent(
          DateTime(2026, 10, 12, 18),
          DateTime(2026, 10, 12, 19),
        ),
      ),
    );

    final rest = await (db.select(
      db.events,
    )..where((row) => row.id.equals(newId))).getSingle();
    expect(rest.rrule, equals('FREQ=WEEKLY;COUNT=5'));
    expect(
      jsonDecode(rest.exceptions),
      equals({
        '2026-10-26T18:00': {'cancelled': true},
      }),
    );
  });

  test('two cancels from one snapshot keep both', () async {
    SharedPreferences.setMockInitialValues({});
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(await LocalSettings.open()),
        deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
      ],
    );
    addTearDown(container.dispose);
    final calendar = container.read(calendarRepositoryProvider);
    final calendarId = await calendar.createCalendar(
      name: 'Family',
      colorToken: ColorTokens.blue,
    );
    final id = await calendar.createEvent(
      calendarId: calendarId,
      draft: EventDraft(
        title: 'Swimming',
        rrule: 'FREQ=WEEKLY',
        time: RecurringEvent(
          DateTime(2026, 9, 7, 17),
          DateTime(2026, 9, 7, 18),
        ),
      ),
    );
    final CalendarEvent? snapshot = await container
        .read(calendarRepositoryProvider)
        .watchEvent(id)
        .first;

    await calendar.cancelOccurrence(snapshot!, DateTime(2026, 9, 14, 17));
    await calendar.cancelOccurrence(snapshot, DateTime(2026, 9, 21, 17));

    final row = await (db.select(
      db.events,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(jsonDecode(row.exceptions), hasLength(2));
  });
}
