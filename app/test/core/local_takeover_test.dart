import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/sync/local_takeover.dart';
import 'package:hiwiski/core/sync/local_writes.dart';
import 'package:hiwiski/core/sync/outbox.dart';
import 'package:hiwiski/core/sync/sync_engine.dart';
import 'package:hiwiski/data/todo/todo_repository.dart';
import 'package:hiwiski/data/wiki/wiki_repository.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';

import '../support/fakes.dart';

/// Without a server every change still goes into the outbox; connecting sends it.
/// Compacted, it is one creation per item, in an order the server accepts.
void main() {
  late HiwiskiDatabase db;
  late TodoRepository todos;
  late WikiRepository wiki;
  late LocalTakeover takeover;

  setUp(() {
    db = HiwiskiDatabase(NativeDatabase.memory());
    final writes = LocalWrites(db: db, outbox: Outbox(db), sync: _NoSync());
    todos = TodoRepository(
      db: db,
      writes: writes,
      currentMemberId: () => 'local-anna',
    );
    wiki = WikiRepository(
      db: db,
      writes: writes,
      api: HiwiskiApi(tokens: NoTokens()),
      currentMemberId: () => 'local-anna',
    );
    takeover = LocalTakeover(db);
  });

  tearDown(() => db.close());

  Future<List<OutboxRow>> outbox() =>
      (db.select(db.outboxEntries)..orderBy([
            (entry) => OrderingTerm.asc(entry.createdAt),
            (entry) => OrderingTerm.asc(entry.mutationId),
          ]))
          .get();

  Map<String, dynamic> fieldsOf(OutboxRow entry) =>
      jsonDecode(entry.fields) as Map<String, dynamic>;

  Future<void> compact() => takeover.compact(deletedBefore: DateTime(2000));

  test(
    'every change of an item becomes one creation with its fields now',
    () async {
      final listId = await todos.createList(name: 'Home', kind: 'STANDARD');
      final id = await todos.createTodo(listId: listId, title: 'Bins');
      final todo = (await todos.watchTodo(id).first)!;
      await todos.updateTodo(todo, title: 'Bins out');
      await todos.setStatus((await todos.watchTodo(id).first)!, true);
      expect(await outbox(), hasLength(4));

      await compact();

      final entries = await outbox();
      expect(entries, hasLength(2));
      final task = entries.singleWhere((entry) => entry.entityId == id);
      expect(task.baseVersion, isNull);
      expect(task.op, equals('upsert'));
      expect(fieldsOf(task)['title'], equals('Bins out'));
      expect(fieldsOf(task)['status'], equals('DONE'));
      expect(task.containerId, equals(listId));
    },
  );

  test('what was deleted, and what was in it, does not go out', () async {
    final kept = await todos.createList(name: 'Home', kind: 'STANDARD');
    final goneList = await todos.createList(name: 'Old', kind: 'STANDARD');
    await todos.createTodo(listId: goneList, title: 'In the old list');
    final goneTodo = await todos.createTodo(listId: kept, title: 'Done with');
    await todos.deleteTodo((await todos.watchTodo(goneTodo).first)!);
    await todos.deleteList((await todos.watchList(goneList).first)!);

    await compact();

    final entries = await outbox();
    expect(entries.map((entry) => entry.entityId), equals([kept]));
    // The rows stay, for the trash.
    expect(await todos.watchTodo(goneTodo).first, isNotNull);
  });

  test('containers go first, a page after its parent', () async {
    final child = await wiki.createPage(title: 'Child');
    final parent = await wiki.createPage(title: 'Parent');
    final listId = await todos.createList(name: 'Home', kind: 'STANDARD');
    await todos.createTodo(listId: listId, title: 'Bins');
    await wiki.movePage((await wiki.watchPage(child).first)!, parent);

    await compact();

    final entries = await outbox();
    final order = [for (final entry in entries) entry.entityId];
    expect(order.indexOf(parent), lessThan(order.indexOf(child)));
    expect(
      entries.indexWhere((entry) => entry.entityType == 'TODO_LIST'),
      lessThan(entries.indexWhere((entry) => entry.entityType == 'TODO')),
    );
    final moved = entries.singleWhere((entry) => entry.entityId == child);
    final parentEntry = entries.singleWhere(
      (entry) => entry.entityId == parent,
    );
    expect(moved.dependsOn, equals(parentEntry.mutationId));
    expect(fieldsOf(moved)['parentId'], equals(parent));
  });

  test('a restored item goes out again, with its fields', () async {
    final listId = await todos.createList(name: 'Home', kind: 'STANDARD');
    await todos.deleteList((await todos.watchList(listId).first)!);
    await (db.update(db.todoLists)..where((row) => row.id.equals(listId)))
        .write(const TodoListsCompanion(deletedAt: Value(null)));

    await compact();

    final entries = await outbox();
    expect(entries, hasLength(1));
    expect(entries.single.op, equals('upsert'));
    expect(fieldsOf(entries.single)['name'], equals('Home'));
  });

  test(
    'what is deleted before the retention cut-off is gone for good',
    () async {
      final listId = await todos.createList(name: 'Old', kind: 'STANDARD');
      await todos.deleteList((await todos.watchList(listId).first)!);

      await takeover.compact(
        deletedBefore: DateTime.now().add(const Duration(minutes: 1)),
      );

      expect(await db.select(db.todoLists).get(), isEmpty);
      expect(await outbox(), isEmpty);
    },
  );

  test('entries that are not simply waiting are left alone', () async {
    final listId = await todos.createList(name: 'Home', kind: 'STANDARD');
    final todo = await todos.createTodo(listId: listId, title: 'Bins');
    await (db.update(db.outboxEntries)
          ..where((entry) => entry.entityId.equals(todo)))
        .write(const OutboxEntriesCompanion(state: Value('rejected')));
    final before = await outbox();

    await compact();

    final after = await outbox();
    expect(
      after.where((entry) => entry.entityId == todo).single.mutationId,
      equals(before.where((entry) => entry.entityId == todo).single.mutationId),
    );
  });

  test(
    'signing in to another account rewrites the member everywhere',
    () async {
      final listId = await todos.createList(
        name: 'Home',
        kind: 'STANDARD',
        assignees: ['local-anna'],
      );
      await todos.setListOrder([listId]);

      await takeover.rewriteMember('local-anna', 'server-anna');
      await takeover.yieldToExistingAccount();

      final list = (await db.select(db.todoLists).get()).single;
      expect(list.ownerId, equals('server-anna'));
      expect(list.assignees, equals('server-anna'));
      final order = (await db.select(db.listOrders).get()).single;
      expect(order.id, equals('server-anna'));
      final entries = await outbox();
      expect(
        entries.map((entry) => entry.entityType),
        isNot(contains('LIST_ORDER')),
      );
      expect(
        entries.map((entry) => entry.fields).join(),
        isNot(contains('local-anna')),
      );
      expect(fieldsOf(entries.single)['assignees'], equals(['server-anna']));
    },
  );
}

class _NoSync implements SyncTrigger {
  @override
  Future<void> syncNow() async {}
}
