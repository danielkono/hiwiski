import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, RowIdExtension;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/data/todo/todo_repository.dart';
import 'package:hiwiski/domain/todo/kanban.dart';
import 'package:hiwiski/domain/todo/todo_items.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hiwiski/app/repositories.dart';

/// **Moving a card writes its column — and its status where it crosses the done
/// column**. What goes into the outbox is what the server sees.
void main() {
  late HiwiskiDatabase db;
  late ProviderContainer container;
  late TodoRepository repository;

  const todo = KanbanColumn(id: 'c-todo', name: 'To do');
  const doing = KanbanColumn(id: 'c-doing', name: 'Doing');
  const done = KanbanColumn(id: 'c-done', name: 'Done', done: true);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    db = HiwiskiDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
      ],
    );
    repository = container.read(todoRepositoryProvider);
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  Future<Todo> read(String id) async => (await repository.watchTodo(id).first)!;

  Future<TodoList> readList(String id) async =>
      (await repository.watchList(id).first)!;

  /// The fields of the newest mutation for [id].
  Future<Map<String, dynamic>> lastFields(String id) async {
    // In the outbox's own order — creation, then insertion: without ORDER BY,
    // "last" is whatever SQLite happens to return last.
    final entries =
        await (db.select(db.outboxEntries)
              ..where((row) => row.entityId.equals(id))
              ..orderBy([
                (row) => OrderingTerm.asc(row.createdAt),
                (row) => OrderingTerm.asc(row.rowId),
              ]))
            .get();
    return jsonDecode(entries.last.fields) as Map<String, dynamic>;
  }

  Future<String> board() => repository.createList(
    name: 'Move',
    kind: kindKanban,
    columns: const [todo, doing, done],
  );

  test('a new board carries its columns', () async {
    final id = await board();

    expect(
      parseColumns((await readList(id)).columns),
      equals([todo, doing, done]),
    );
    expect((await lastFields(id))['columns'], hasLength(3));
  });

  test('moving into the done column ticks the card off', () async {
    final listId = await board();
    final id = await repository.createTodo(
      listId: listId,
      title: 'Boxes',
      columnId: doing.id,
    );

    await repository.moveCard(await read(id), done, columnCards: const []);

    final card = await read(id);
    expect(card.status, equals('DONE'));
    expect(card.columnId, equals(done.id));
    expect(
      await lastFields(id),
      equals({'columnId': done.id, 'status': 'DONE', 'position': 0}),
    );
  });

  test('check off moves between columns without a position', () async {
    final listId = await board();
    final id = await repository.createTodo(listId: listId, title: 'Boxes');

    await repository.moveCard(
      await read(id),
      doing,
      columnCards: const [],
      reorder: false,
    );

    expect(await lastFields(id), equals({'columnId': doing.id}));
  });

  test('dropped between two cards, it lands between them', () async {
    final listId = await board();
    final first = await repository.createTodo(
      listId: listId,
      title: 'A',
      columnId: doing.id,
      position: 0,
    );
    final second = await repository.createTodo(
      listId: listId,
      title: 'B',
      columnId: doing.id,
      position: positionStep,
    );
    final moving = await repository.createTodo(listId: listId, title: 'C');

    await repository.moveCard(
      await read(moving),
      doing,
      columnCards: [await read(first), await read(second)],
      index: 1,
    );

    expect((await read(moving)).position, equals(positionStep ~/ 2));
  });

  test('without room the column is renumbered first', () async {
    final listId = await board();
    final first = await repository.createTodo(
      listId: listId,
      title: 'A',
      columnId: doing.id,
    );
    final second = await repository.createTodo(
      listId: listId,
      title: 'B',
      columnId: doing.id,
    );
    final moving = await repository.createTodo(listId: listId, title: 'C');

    await repository.moveCard(
      await read(moving),
      doing,
      columnCards: [await read(first), await read(second)],
      index: 1,
    );

    final positions = [
      (await read(first)).position,
      (await read(moving)).position,
      (await read(second)).position,
    ];
    expect(positions, orderedEquals([...positions]..sort()));
    expect(positions.toSet(), hasLength(3));
  });

  test('ticking a card off moves it into the done column, and back', () async {
    final listId = await board();
    final id = await repository.createTodo(
      listId: listId,
      title: 'Boxes',
      columnId: doing.id,
    );

    await repository.setStatus(await read(id), true);
    expect((await read(id)).columnId, equals(done.id));

    await repository.setStatus(await read(id), false);
    expect((await read(id)).columnId, equals(todo.id));
    expect(
      await lastFields(id),
      equals({'status': 'OPEN', 'columnId': todo.id}),
    );
  });

  test('ticking off on a task list writes no column', () async {
    final listId = await repository.createList(name: 'Home', kind: 'STANDARD');
    final id = await repository.createTodo(listId: listId, title: 'Bins');

    await repository.setStatus(await read(id), true);

    expect(await lastFields(id), equals({'status': 'DONE'}));
  });

  test('removing a column moves its cards to the one before', () async {
    final listId = await board();
    final id = await repository.createTodo(
      listId: listId,
      title: 'Boxes',
      columnId: doing.id,
    );

    await repository.updateColumns(
      await readList(listId),
      const [todo, done],
      [await read(id)],
    );

    expect((await read(id)).columnId, equals(todo.id));
    expect(
      parseColumns((await readList(listId)).columns),
      equals([todo, done]),
    );
  });

  test('a task list becomes a board, and its repeats are dropped', () async {
    final listId = await repository.createList(name: 'Home', kind: 'STANDARD');
    final weekly = await repository.createTodo(
      listId: listId,
      title: 'Bins',
      rrule: 'FREQ=WEEKLY',
    );
    final once = await repository.createTodo(listId: listId, title: 'Paint');

    await repository.convertToKanban(
      await readList(listId),
      const [todo, doing, done],
      [await read(weekly), await read(once)],
    );

    final list = await readList(listId);
    expect(list.kind, equals(kindKanban));
    expect(parseColumns(list.columns), hasLength(3));
    expect((await read(weekly)).rrule, isNull);
    expect(await lastFields(weekly), equals({'rrule': null}));
    // The other card is not touched: an open card without a column stands first.
    final onceEntries = await (db.select(
      db.outboxEntries,
    )..where((row) => row.entityId.equals(once))).get();
    expect(onceEntries, hasLength(1));
  });
}
