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

/// **A task deleted from its row can be taken back for a moment** — offline too: it
/// is deleted for good only once that moment has passed.
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
    listId = await todos.createList(
      name: 'Groceries',
      kind: ListKinds.shopping,
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('taken back, it stays; nothing goes out', () async {
    final id = await todos.createTodo(listId: listId, title: 'Milk');
    final milk = (await todos.watchTodos(listId).first).single;
    final queued = (await db.select(db.outboxEntries).get()).length;

    todos.deleteTodoSoon(milk);
    expect(await todos.watchPendingDeletes().first, equals({id}));
    todos.undoDelete(id);

    expect(await todos.watchPendingDeletes().first, isEmpty);
    await Future<void>.delayed(
      todos.deleteGrace + const Duration(milliseconds: 200),
    );
    expect((await todos.watchTodos(listId).first).single.id, equals(id));
    expect(await db.select(db.outboxEntries).get(), hasLength(queued));
  });

  test('not taken back, it is deleted once the moment has passed', () async {
    final id = await todos.createTodo(listId: listId, title: 'Milk');
    final milk = (await todos.watchTodos(listId).first).single;

    todos.deleteTodoSoon(milk);
    expect(await todos.watchTodos(listId).first, hasLength(1));
    await Future<void>.delayed(
      todos.deleteGrace + const Duration(milliseconds: 200),
    );

    expect(await todos.watchTodos(listId).first, isEmpty);
    expect(await todos.watchPendingDeletes().first, isEmpty);
    final row = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(row.deletedAt, isNotNull);
  });
}
