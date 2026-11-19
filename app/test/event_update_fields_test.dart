import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/data/calendar/calendar_repository.dart';
import 'package:hiwiski/domain/calendar/event_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **Saving an event sends only what changed**. The form hands over the
/// whole event; sent as a whole, a field nobody touched overwrote what another device
/// changed meanwhile, and the history listed every field as changed.
void main() {
  late HiwiskiDatabase db;
  late CalendarRepository calendar;
  late String family;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(await LocalSettings.open()),
        deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
      ],
    );
    addTearDown(container.dispose);
    calendar = container.read(calendarRepositoryProvider);
    family = await calendar.createCalendar(
      name: 'Family',
      colorToken: ColorTokens.blue,
    );
  });

  Future<int> outboxCount() async =>
      (await db.select(db.outboxEntries).get()).length;

  Future<Map<String, dynamic>> lastSent() async =>
      jsonDecode((await db.select(db.outboxEntries).get()).last.fields)
          as Map<String, dynamic>;

  /// Creates [draft], then saves [edited] over it.
  Future<void> edit(EventDraft draft, EventDraft edited) async {
    final id = await calendar.createEvent(calendarId: family, draft: draft);
    final event = await calendar.watchEvent(id).first;
    await calendar.updateEvent(event!, edited);
  }

  final timed = TimedEvent(
    DateTime(2026, 10, 12, 8),
    DateTime(2026, 10, 12, 9),
  );

  test('a new title sends the title alone', () async {
    await edit(
      EventDraft(title: 'Dentist', time: timed, location: 'Main St'),
      EventDraft(title: 'Dentist, Ben', time: timed, location: 'Main St'),
    );

    expect((await lastSent()).keys, equals([WireFields.title]));
  });

  test(
    'a series of whole days sends its time zone only when it changes',
    () async {
      final days = AllDayEvent(DateTime(2026, 10, 12), DateTime(2026, 10, 13));
      const rrule = 'FREQ=WEEKLY';
      await edit(
        EventDraft(title: 'Swimming', time: days, rrule: rrule, tags: ['t1']),
        EventDraft(title: 'Swimming', time: days, rrule: rrule, tags: ['t2']),
      );

      expect((await lastSent()).keys, equals([WireFields.tags]));
    },
  );

  test('another time form clears the fields of the old one', () async {
    await edit(
      EventDraft(title: 'Dentist', time: timed),
      EventDraft(
        title: 'Dentist',
        time: AllDayEvent(DateTime(2026, 10, 12), DateTime(2026, 10, 13)),
      ),
    );

    expect(
      await lastSent(),
      equals({
        WireFields.timeForm: TimeForms.allDay,
        WireFields.startDate: '2026-10-12',
        WireFields.endDate: '2026-10-13',
        WireFields.startsAt: null,
        WireFields.endsAt: null,
      }),
    );
  });

  test('saving without a change sends nothing', () async {
    final draft = EventDraft(title: 'Dentist', time: timed, tags: ['t1']);
    await edit(draft, draft);

    expect(await outboxCount(), equals(2), reason: 'calendar and event');
  });
}
