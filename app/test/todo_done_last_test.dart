import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/data/todo/todo_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **Ticked-off rows move to the bottom — or stay put** (Account → Customize).
void main() {
  late HiwiskiDatabase db;
  late ProviderContainer container;
  late TodoRepository todos;
  late String listId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = HiwiskiDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(await LocalSettings.open()),
      ],
    );
    todos = container.read(todoRepositoryProvider);
    listId = await todos.createList(name: 'Home', kind: ListKinds.standard);
    for (final title in ['A', 'B', 'C']) {
      await todos.createTodo(listId: listId, title: title);
    }
    final first = (await todos.watchTodos(listId).first).first;
    await todos.setStatus(first, true);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('by default the ticked-off row goes to the bottom', () async {
    final titles = [
      for (final t in await todos.watchTodos(listId).first) t.title,
    ];
    expect(titles, equals(['B', 'C', 'A']));
  });

  test('switched off, it keeps its place', () async {
    final rows = await todos.watchTodos(listId, doneLast: false).first;
    expect([for (final t in rows) t.title], equals(['A', 'B', 'C']));
    expect(rows.first.status, equals(TodoStatuses.done));
  });

  test('the setting is remembered on the device, on by default', () async {
    final settings = await LocalSettings.open();
    expect(settings.doneLast, isTrue);
    await settings.setDoneLast(false);
    expect((await LocalSettings.open()).doneLast, isFalse);
  });
}
