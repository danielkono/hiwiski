import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/sync/entity_codec.dart';
import 'package:hiwiski/core/sync/left_behind.dart';
import 'package:hiwiski/core/sync/outbox.dart';
import 'package:hiwiski/data/sync/sync_repository.dart';

/// **A server lost and restored from a week-old backup loses nothing the phones saw.**
/// The mirror goes, a copy of it stays; of the copy, what the restored server does not
/// have — or has older — waits to be brought back. What it has as it was goes.
void main() {
  late HiwiskiDatabase db;
  late LeftBehind left;

  setUp(() {
    db = HiwiskiDatabase(NativeDatabase.memory());
    left = LeftBehind(db);
  });
  tearDown(() => db.close());

  Future<void> list(String id, String name, int version) =>
      const TodoListCodec().upsert(
        db,
        id: id,
        ownerId: 'anna',
        version: version,
        containerId: null,
        entityKey: null,
        fields: {WireFields.name: name, WireFields.kind: ListKinds.shopping},
      );

  Future<void> todo(
    String id,
    String title,
    int version, {
    String list = 'l1',
  }) => const TodoCodec().upsert(
    db,
    id: id,
    ownerId: 'anna',
    version: version,
    containerId: list,
    entityKey: null,
    fields: {WireFields.title: title, WireFields.status: TodoStatuses.done},
  );

  /// The device before the restore, the restore, the restored state coming in.
  Future<void> restoreWith(AsyncCallback server) async {
    await left.capture();
    await db.discardMirroredData();
    await server();
    await left.settle();
  }

  test('what the server lost or has older waits; what it kept goes', () async {
    await list('l1', 'Wocheneinkauf', 3);
    await todo('t1', 'Obst', 5);
    await list('l2', 'Baumarkt', 2);
    await todo('t2', 'Schrauben', 1, list: 'l2');
    // Not sent yet: it goes out by itself, nothing to keep.
    await todo('t3', 'Milch', 2);
    await Outbox(db).add(
      entityType: EntityTypes.todo,
      entityId: 't3',
      op: SyncOps.upsert,
      fields: {WireFields.status: TodoStatuses.done},
    );

    // The backup knew the list as it is, "Obst" before it was ticked, and not the
    // DIY list at all.
    await restoreWith(() async {
      await list('l1', 'Wocheneinkauf', 3);
      await todo('t1', 'Obst', 4);
      await todo('t3', 'Milch', 2);
    });

    final kept = await left.watch().first;
    expect({for (final row in kept) row.entityId}, equals({'t1', 'l2', 't2'}));
  });

  test(
    'brought back, it goes out containers first and builds on the server',
    () async {
      await list('l2', 'Baumarkt', 2);
      await todo('t2', 'Schrauben', 1, list: 'l2');
      await todo('t1', 'Obst', 5);
      await restoreWith(() => todo('t1', 'Obst', 4));

      await left.restore();

      final queued = await Outbox(db).pending(limit: 10);
      expect(queued.first.entityId, equals('l2'), reason: 'the list first');
      expect({
        for (final entry in queued) entry.entityId,
      }, equals({'l2', 't2', 't1'}));
      final obst = queued.firstWhere((entry) => entry.entityId == 't1');
      expect(obst.baseVersion, equals(4), reason: "on the server's version");
      expect(
        (jsonDecode(obst.fields) as Map)[WireFields.status],
        equals(TodoStatuses.done),
      );
      final screws = queued.firstWhere((entry) => entry.entityId == 't2');
      expect(screws.baseVersion, isNull, reason: 'new to the server');
      expect(screws.dependsOn, equals(queued.first.mutationId));
      // In the mirror again at once, and nothing left to decide.
      expect(await const TodoCodec().stored(db, 't2'), isNotNull);
      expect(await left.watch().first, isEmpty);
    },
  );

  test('a deletion the restore undid is done again', () async {
    await todo('t1', 'Alt', 3);
    await const TodoCodec().markDeleted(db, 't1', 4);
    await restoreWith(() => todo('t1', 'Alt', 3));

    expect(await left.watch().first, hasLength(1));
    await left.restore();

    final queued = await Outbox(db).pending(limit: 10);
    expect(queued.single.op, equals(SyncOps.delete));
    expect(queued.single.baseVersion, equals(3));
  });

  group('a mind map', () {
    Future<void> page() => const WikiPageCodec().upsert(
      db,
      id: 'p1',
      ownerId: 'anna',
      version: 2,
      containerId: null,
      entityKey: null,
      fields: {
        WireFields.title: 'Urlaub',
        WireFields.kind: PageKinds.mindmap,
        WireFields.position: 0,
        WireFields.content: '',
      },
    );
    Future<void> node(String id, String kind, String text) =>
        const MindmapNodeCodec().upsert(
          db,
          id: id,
          ownerId: 'anna',
          version: 1,
          containerId: 'p1',
          entityKey: null,
          fields: {
            WireFields.kind: kind,
            WireFields.x: 0,
            WireFields.y: 0,
            WireFields.width: 100,
            WireFields.height: 40,
            WireFields.layer: 1,
            WireFields.text: text,
          },
        );

    setUp(() async {
      await page();
      await node('n1', MindmapKinds.note, '# Packliste\n- Sonnencreme');
      await node('n2', MindmapKinds.image, '![](hiwiski-image://i1)');
      await const MindmapEdgeCodec().upsert(
        db,
        id: 'e1',
        ownerId: 'anna',
        version: 1,
        containerId: 'p1',
        entityKey: null,
        fields: {
          WireFields.fromId: 'n1',
          WireFields.toId: 'n2',
          WireFields.text: '',
        },
      );
      // The backup knew the page, not its map.
      await restoreWith(page);
    });

    test('a connection brought back brings its elements along', () async {
      await left.restore(keys: {(EntityTypes.mindmapEdge, 'e1')});

      final queued = await Outbox(db).pending(limit: 10);
      expect([
        for (final entry in queued) entry.entityId,
      ], equals(['n1', 'n2', 'e1']));
      // After both of its elements.
      expect(queued.last.dependsOn, equals(queued[1].mutationId));
      expect(await left.watch().first, isEmpty);
    });

    test('its items are named by their own words or their kind', () async {
      final items = {
        for (final row in await left.watch().first)
          row.entityId: SyncRepository.leftBehindOf(row).label,
      };
      expect(items, equals({'n1': 'Packliste', 'n2': '', 'e1': ''}));
    });
  });

  test('let go, it is gone', () async {
    await todo('t1', 'Obst', 5);
    await restoreWith(() async {});

    await left.discard();

    expect(await left.watch().first, isEmpty);
    expect(await Outbox(db).pending(limit: 10), isEmpty);
  });
}
