import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/api/hiwiski_failure.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/storage/local_image_store.dart';
import 'package:hiwiski/core/sync/local_takeover.dart';
import 'package:hiwiski/core/sync/local_writes.dart';
import 'package:hiwiski/core/sync/outbox.dart';
import 'package:hiwiski/core/sync/sync_engine.dart';
import 'package:hiwiski/data/admin/local_trash.dart';
import 'package:hiwiski/data/media/media_repository.dart';
import 'package:hiwiski/data/todo/todo_repository.dart';
import 'package:hiwiski/data/wiki/mindmap_repository.dart';
import 'package:hiwiski/data/wiki/wiki_repository.dart';

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

  test('a mind map comes back with its page — and goes out in full', () async {
    final wiki = WikiRepository(
      db: db,
      writes: writes,
      api: HiwiskiApi(tokens: NoTokens()),
      currentMemberId: () => 'anna',
    );
    final maps = MindmapRepository(
      db: db,
      writes: writes,
      currentMemberId: () => 'anna',
    );
    final pageId = await wiki.createPage(
      title: 'Urlaub',
      kind: PageKinds.mindmap,
    );
    Future<String> element(String text) => maps.addNode(
      pageId: pageId,
      kind: MindmapKinds.plain,
      x: 0,
      y: 0,
      width: 100,
      height: 40,
      text: text,
    );
    final kept = await element('Meer');
    final other = await element('Berge');
    final earlier = await element('Wüste');
    await maps.connect((await maps.node(kept))!, (await maps.node(other))!);
    final day = DateTime.utc(2026, 11, 20, 10);
    await withClock(
      .fixed(day),
      () async => maps.deleteNode((await maps.node(earlier))!),
    );
    await withClock(
      .fixed(day.add(const Duration(hours: 1))),
      () async => wiki.deletePage((await wiki.watchPage(pageId).first)!),
    );
    // A start without a server: what never left the device and lies in the trash
    // goes out of the outbox.
    await LocalTakeover(db).compact(deletedBefore: DateTime.utc(2026, 10));
    expect(await _entriesOf(db, kept), isEmpty);

    await trash.restore(EntityTypes.wikiPage, pageId);

    final map = await maps.watchMap(pageId).first;
    expect([
      for (final node in map.nodes) node.text,
    ], unorderedEquals(['Meer', 'Berge']));
    expect(map.edges, hasLength(1));
    // Deleted on its own before the page went: it stays deleted.
    expect(await maps.node(earlier), isNull);
    final [revived] = await _entriesOf(db, kept);
    expect(
      jsonDecode(revived.fields),
      allOf(
        containsPair(WireFields.kind, MindmapKinds.plain),
        containsPair(WireFields.text, 'Meer'),
      ),
    );
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

Future<List<OutboxRow>> _entriesOf(HiwiskiDatabase db, String id) => (db.select(
  db.outboxEntries,
)..where((row) => row.entityId.equals(id))).get();

class _NoSync implements SyncTrigger {
  @override
  Future<void> syncNow() async {}
}
