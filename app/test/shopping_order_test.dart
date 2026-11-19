import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/sync/local_writes.dart';
import 'package:hiwiski/core/sync/outbox.dart';
import 'package:hiwiski/core/sync/sync_engine.dart';
import 'package:hiwiski/domain/todo/todo_items.dart';
import 'package:hiwiski/data/todo/todo_repository.dart';

/// **The rows of a shopping list are sorted by hand** within their categories:
/// the order is the rows' positions.
void main() {
  late HiwiskiDatabase db;
  late TodoRepository todos;

  setUp(() {
    db = HiwiskiDatabase(NativeDatabase.memory());
    todos = TodoRepository(
      db: db,
      writes: LocalWrites(db: db, outbox: Outbox(db), sync: _NoSync()),
      currentMemberId: () => 'anna',
    );
  });

  tearDown(() => db.close());

  Future<List<String>> order(String listId) async => [
    for (final todo in await todos.watchTodos(listId).first) todo.title,
  ];

  test('a new row goes to the end of a shopping list', () async {
    final list = await todos.createList(name: 'Shop', kind: ListKinds.shopping);
    await todos.createTodo(listId: list, title: 'Milk');
    await todos.createTodo(listId: list, title: 'Apples');

    // Not by title: the one added last is last.
    expect(await order(list), equals(['Milk', 'Apples']));
  });

  // Every kind of list, not only shopping lists: a card created from "New task" on a
  // board landed at the top of its column.
  test('a new card goes to the end of its column', () async {
    final list = await todos.createList(name: 'Board', kind: ListKinds.kanban);
    final first = await todos.createTodo(listId: list, title: 'Plan');
    final second = await todos.createTodo(listId: list, title: 'Build');
    final rows = await todos.watchTodos(list).first;
    int position(String id) =>
        rows.firstWhere((todo) => todo.id == id).position;

    expect(position(second), greaterThan(position(first)));
  });

  // Two quick entries read the same end before either was inserted.
  test('two entries at once both go to the end, in order', () async {
    final list = await todos.createList(name: 'Shop', kind: ListKinds.shopping);
    await Future.wait([
      todos.createTodo(listId: list, title: 'Zucchini'),
      todos.createTodo(listId: list, title: 'Apples'),
    ]);

    expect(await order(list), equals(['Zucchini', 'Apples']));
  });

  test(
    'a row is put between two, renumbering where there is no room',
    () async {
      final list = await todos.createList(
        name: 'Shop',
        kind: ListKinds.shopping,
      );
      for (final title in ['Apples', 'Bread', 'Cheese']) {
        await todos.createTodo(listId: list, title: title);
      }
      final rows = await todos.watchTodos(list).first;
      Todo row(String title) => rows.firstWhere((todo) => todo.title == title);

      await todos.reposition(
        row('Cheese'),
        others: [row('Apples'), row('Bread')],
        at: 0,
      );
      expect(await order(list), equals(['Cheese', 'Apples', 'Bread']));

      final now = await todos.watchTodos(list).first;
      Todo current(String title) => now.firstWhere((t) => t.title == title);
      await todos.reposition(
        current('Bread'),
        others: [current('Cheese'), current('Apples')],
        at: 1,
      );
      expect(await order(list), equals(['Cheese', 'Bread', 'Apples']));
    },
  );

  test('a task list keeps adding at position 0', () async {
    final list = await todos.createList(name: 'Home', kind: 'STANDARD');
    final id = await todos.createTodo(listId: list, title: 'Bins');

    expect((await todos.watchTodo(id).first)!.position, equals(0));
  });
}

class _NoSync implements SyncTrigger {
  @override
  Future<void> syncNow() async {}
}
