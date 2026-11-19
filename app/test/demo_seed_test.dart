import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'support/fakes.dart';

/// The public demo's sample data: both languages say the same, and
/// they go into the app through its repositories, as a member's input would.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  Map<String, dynamic> read(String language) =>
      jsonDecode(File('assets/demo/demo-$language.json').readAsStringSync())
          as Map<String, dynamic>;

  /// The shape of the data without its words: keys, counts, numbers.
  Object? shape(Object? value) => switch (value) {
    final Map<String, dynamic> map => {
      for (final MapEntry(:key, :value) in map.entries)
        key: switch (key) {
          'name' ||
          'title' ||
          'content' ||
          'description' ||
          'me' ||
          'label' ||
          'location' => '',
          'unit' => value == null ? null : '',
          _ => shape(value),
        },
    },
    final List<dynamic> list => [for (final item in list) shape(item)],
    _ => value,
  };

  test('both languages hold the same sample data', () {
    expect(shape(read('de')), equals(shape(read('en'))));
  });

  test('the demo writes its sample data through the repositories', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      retry: noRetry,
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
        hiwiskiApiProvider.overrideWithValue(HiwiskiApi(tokens: NoTokens())),
        deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
        sessionFrom(const SessionState(stage: .localOnly)),
      ],
    );
    addTearDown(container.dispose);

    await container.read(demoProvider).start();

    final session = container.read(sessionProvider);
    expect(session.stage, equals(SessionStage.localOnly));
    expect(session.member?.displayName, equals('Anna Sonnenberg'));
    final data = read('en');
    expect(
      await db.select(db.todoLists).get(),
      hasLength((data['lists'] as List).length),
    );
    expect(
      await db.select(db.calendars).get(),
      hasLength((data['calendars'] as List).length),
    );
    int pages(Object? entries) => [
      for (final page in (entries as List? ?? const []).cast<Map>())
        1 + pages(page['children']),
    ].fold(0, (sum, count) => sum + count);
    expect(
      await db.select(db.wikiPages).get(),
      hasLength(pages(data['pages'])),
    );
    // Pages sit under their parents, and recipes under their collections.
    final rows = await db.select(db.wikiPages).get();
    expect(rows.where((row) => row.parentId != null), isNotEmpty);
    expect(
      rows.where((row) => row.kind == 'RECIPE' && row.parentId != null),
      isNotEmpty,
    );
    // Pages link to pages and to lists, by the address the link picker writes; no
    // placeholder of the sample data is left over.
    final texts = rows.map((row) => row.content).join('\n');
    expect(texts, isNot(contains('{{')));
    expect(texts, contains('](hiwiski://wiki_page/'));
    expect(texts, contains('](hiwiski://todo_list/'));
    // Lists and pages carry tags, as tasks and events do.
    expect(rows.where((row) => row.tags.isNotEmpty), isNotEmpty);
    expect(
      (await db.select(db.todoLists).get()).where((l) => l.tags.isNotEmpty),
      isNotEmpty,
    );
    // Cards stand in their columns; what is done is done.
    final lists = (data['lists'] as List).cast<Map<String, dynamic>>();
    final todos = await db.select(db.todos).get();
    expect(
      todos,
      hasLength(
        lists.fold<int>(0, (sum, l) => sum + (l['items'] as List).length),
      ),
    );
    final done = [
      for (final list in lists)
        for (final item in (list['items'] as List).cast<Map>())
          if (item['done'] == true) item,
    ];
    expect(
      todos.where((todo) => todo.status == 'DONE'),
      hasLength(done.length),
    );
    final boards = (await db.select(db.todoLists).get()).where(
      (list) => list.kind == 'KANBAN',
    );
    expect(boards, isNotEmpty);
    for (final board in boards) {
      for (final card in todos.where((todo) => todo.listId == board.id)) {
        expect(card.columnId, isNotNull, reason: card.title);
      }
    }
    expect(
      await db.select(db.members).get(),
      hasLength((data['family'] as List).length + 1),
    );
    // A year of the family: every event starts between today and a year from now —
    // birthdays and holidays on their next date, series on a day their rule holds.
    final calendars = (data['calendars'] as List).cast<Map<String, dynamic>>();
    final events = await db.select(db.events).get();
    expect(
      events,
      hasLength(
        calendars.fold<int>(0, (sum, c) => sum + (c['events'] as List).length),
      ),
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final event in events) {
      final start = switch (event.localStart) {
        final String local => DateTime.parse(local),
        null => (event.startDate ?? event.startsAt)!.toLocal(),
      };
      expect(
        start.isBefore(today) ||
            start.isAfter(DateTime(today.year + 1, today.month, today.day + 1)),
        isFalse,
        reason: '${event.title} starts on $start',
      );
    }
    final widgets = await db.select(db.widgets).get();
    expect(widgets, hasLength((data['start'] as List).length));

    // Reset: the same again, nothing twice.
    await container.read(demoProvider).reset();
    expect(
      await db.select(db.todoLists).get(),
      hasLength((data['lists'] as List).length),
    );
  });
}
