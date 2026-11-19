import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/domain/calendar/event_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hiwiski/app/repositories.dart';

/// **Picking another calendar for an existing event moves it.** The picker changed
/// the sheet, but neither the local row nor the outbox mutation carried the
/// calendar: the event stayed where it was, without a word.
void main() {
  test('an edited event moves to the calendar picked for it', () async {
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
    final family = await calendar.createCalendar(
      name: 'Family',
      colorToken: ColorTokens.blue,
    );
    final work = await calendar.createCalendar(
      name: 'Work',
      colorToken: ColorTokens.blue,
    );
    final draft = EventDraft(
      title: 'Dentist',
      time: TimedEvent(DateTime(2026, 10, 12, 8), DateTime(2026, 10, 12, 9)),
    );
    final id = await calendar.createEvent(calendarId: family, draft: draft);
    final event = await container
        .read(calendarRepositoryProvider)
        .watchEvent(id)
        .first;

    await calendar.updateEvent(event!, draft, calendarId: work);

    final row = await (db.select(
      db.events,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(row.calendarId, equals(work));
    final last = (await db.select(db.outboxEntries).get()).last;
    expect(last.containerId, equals(work));
    expect(jsonDecode(last.fields), containsPair(WireFields.calendarId, work));
  });
}
