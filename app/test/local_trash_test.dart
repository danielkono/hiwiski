import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/api/hiwiski_failure.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_image_store.dart';
import 'package:hiwiski/core/sync/local_writes.dart';
import 'package:hiwiski/core/sync/outbox.dart';
import 'package:hiwiski/core/sync/sync_engine.dart';
import 'package:hiwiski/data/admin/local_trash.dart';
import 'package:hiwiski/data/media/media_repository.dart';
import 'package:hiwiski/data/todo/todo_repository.dart';

import 'support/fakes.dart';

/// What a device without a server keeps of what was deleted, and the images it
/// keeps itself.
void main() {
  late HiwiskiDatabase db;
  late LocalWrites writes;
  late TodoRepository todos;
  late LocalTrash trash;

  setUp(() {
    db = HiwiskiDatabase(NativeDatabase.memory());
    writes = LocalWrites(db: db, outbox: Outbox(db), sync: _NoSync());
    todos = TodoRepository(
      db: db,
      writes: writes,
      currentMemberId: () => 'anna',
    );
    trash = LocalTrash(db: db, writes: writes);
  });

  tearDown(() => db.close());

  test('a deleted task is in the trash and comes back', () async {
    final listId = await todos.createList(name: 'Home', kind: 'STANDARD');
    final id = await todos.createTodo(listId: listId, title: 'Bins');
    await todos.deleteTodo((await todos.watchTodo(id).first)!);

    final entry = (await trash.list()).entries.single;
    expect(entry.itemType, equals('TODO'));
    expect(entry.title, equals('Bins'));
    expect(entry.restorable, isTrue);
    expect(entry.remainingDays, equals(30));

    await trash.restore('TODO', id);

    expect((await trash.list()).entries, isEmpty);
    expect(await todos.watchTodos(listId).first, hasLength(1));
  });

  test('a task whose list is gone goes back only somewhere else', () async {
    final old = await todos.createList(name: 'Old', kind: 'STANDARD');
    final other = await todos.createList(name: 'Home', kind: 'STANDARD');
    final id = await todos.createTodo(listId: old, title: 'Bins');
    await todos.deleteTodo((await todos.watchTodo(id).first)!);
    await todos.deleteList((await todos.watchList(old).first)!);

    final entry = (await trash.list()).entries.singleWhere(
      (entry) => entry.itemId == id,
    );
    expect(entry.restorable, isFalse);
    await expectLater(
      trash.restore('TODO', id),
      throwsA(
        isA<HiwiskiFailure>().having(
          (f) => f.code,
          'code',
          FailureCodes.trashContainerGone,
        ),
      ),
    );

    await trash.restore('TODO', id, targetContainerId: other);

    expect(await todos.watchTodos(other).first, hasLength(1));
  });

  test('an image added without a server is kept on the device', () async {
    final media = MediaRepository(
      HiwiskiApi(tokens: NoTokens()),
      localImages: LocalImageStore(db),
      outbox: Outbox(db),
      serverless: true,
    );
    final bytes = Uint8List.fromList([1, 2, 3]);

    final id = await media.upload(
      ownerType: 'WIKI_PAGE',
      ownerItemId: 'page',
      bytes: bytes,
      filename: 'a.png',
    );

    expect(await media.image(id, preview: true), equals(bytes));
    expect(await media.carryOver(), isEmpty);
  });
}

class _NoSync implements SyncTrigger {
  @override
  Future<void> syncNow() async {}
}
