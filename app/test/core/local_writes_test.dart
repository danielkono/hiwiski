import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/sync/local_writes.dart';
import 'package:hiwiski/core/sync/outbox.dart';
import 'package:hiwiski/core/sync/sync_engine.dart';

/// **The local database and the outbox do not drift apart.**
///
/// A synced row written without its mutation was never synced — no error, no banner —
/// and the next pulled change overwrote it. Every change goes through [LocalWrites]:
/// the row and its outbox entry in one transaction, both or neither.
void main() {
  late HiwiskiDatabase db;
  late _CountingSync sync;
  late LocalWrites writes;

  setUp(() {
    db = HiwiskiDatabase(NativeDatabase.memory());
    sync = _CountingSync();
    writes = LocalWrites(db: db, outbox: Outbox(db), sync: sync);
  });

  tearDown(() => db.close());

  Future<List<OutboxRow>> outbox() => db.select(db.outboxEntries).get();

  TagsCompanion tag(String id, String name) =>
      .insert(id: id, ownerId: 'anna', name: Value(name));

  test('a created row goes out with its entity type and id', () async {
    await writes.run(
      (write) => write.create(
        db.tags,
        tag('t1', 'Garden'),
        fields: {WireFields.name: 'Garden'},
        label: 'Garden',
      ),
    );

    final entry = (await outbox()).single;
    expect(entry.entityType, equals(EntityTypes.tag));
    expect(entry.entityId, equals('t1'));
    expect(entry.op, equals(SyncOps.upsert));
    expect(jsonDecode(entry.fields), equals({WireFields.name: 'Garden'}));
    expect(entry.baseVersion, isNull);
    expect(await db.select(db.tags).get(), hasLength(1));
  });

  test('a run that fails leaves neither the row nor the entry', () async {
    await expectLater(
      writes.run((write) async {
        await write.create(
          db.tags,
          tag('t1', 'Garden'),
          fields: {WireFields.name: 'Garden'},
          label: 'Garden',
        );
        throw StateError('after the write');
      }),
      throwsStateError,
    );

    expect(await db.select(db.tags).get(), isEmpty);
    expect(await outbox(), isEmpty);
    expect(sync.nudges, equals(0));
  });

  test(
    'a change builds on the version seen and waits for the one before',
    () async {
      await db.into(db.tags).insert(tag('t1', 'Garden'));
      await db.update(db.tags).write(const TagsCompanion(version: Value(4)));

      Future<void> rename(String name) => writes.run(
        (write) => write.change(
          db.tags,
          TagsCompanion(name: Value(name)),
          id: 't1',
          version: 4,
          fields: {WireFields.name: name},
          label: name,
        ),
      );
      await rename('Yard');
      await rename('Lawn');

      final [first, second] = await outbox();
      expect(first.baseVersion, equals(4));
      expect(first.dependsOn, isNull);
      expect(second.dependsOn, equals(first.mutationId));
      expect((await db.select(db.tags).getSingle()).name, equals('Lawn'));
    },
  );

  test('a change does not write a row other than its own', () async {
    await db.into(db.tags).insert(tag('t1', 'Garden'));

    await expectLater(
      writes.run(
        (write) => write.change(
          db.tags,
          tag('t2', 'Yard'),
          id: 't1',
          version: 0,
          fields: {WireFields.name: 'Yard'},
          label: 'Yard',
        ),
      ),
      throwsArgumentError,
    );
    expect((await db.select(db.tags).getSingle()).name, equals('Garden'));
    expect(await outbox(), isEmpty);
  });

  test('a delete leaves a tombstone and sends it', () async {
    await db.into(db.tags).insert(tag('t1', 'Garden'));

    await writes.run(
      (write) => write.delete(db.tags, id: 't1', version: 0, label: 'Garden'),
    );

    expect((await db.select(db.tags).getSingle()).deletedAt, isNotNull);
    expect((await outbox()).single.op, equals(SyncOps.delete));
  });

  test('a cascade follows a mutation of its own run only', () async {
    await db.into(db.tags).insert(tag('t1', 'Garden'));
    await db.into(db.tags).insert(tag('t2', 'Yard'));
    final earlier = await writes.run(
      (write) => write.delete(db.tags, id: 't1', version: 0, label: 'Garden'),
    );

    await expectLater(
      writes.run(
        (write) => write.cascade(
          earlier,
          db.tags,
          TagsCompanion(deletedAt: Value(DateTime.now())),
          where: (row) => row.id.equals('t2'),
        ),
      ),
      throwsArgumentError,
    );
    final t2 = await (db.select(
      db.tags,
    )..where((row) => row.id.equals('t2'))).getSingle();
    expect(t2.deletedAt, isNull);
  });

  test('a LocalWrite is spent once its run is over', () async {
    late LocalWrite kept;
    await writes.run((write) async => kept = write);

    expect(
      () => kept.create(
        db.tags,
        tag('t1', 'Garden'),
        fields: const {},
        label: 'Garden',
      ),
      throwsStateError,
    );
    expect(await db.select(db.tags).get(), isEmpty);
  });

  test('the sync is nudged once per run that queued something', () async {
    await writes.run((write) async {
      await write.create(db.tags, tag('t1', 'A'), fields: const {}, label: 'A');
      await write.create(db.tags, tag('t2', 'B'), fields: const {}, label: 'B');
    });
    await writes.run((write) async => db.select(db.tags).get());

    expect(sync.nudges, equals(1));
  });
}

class _CountingSync implements SyncTrigger {
  int nudges = 0;

  @override
  Future<void> syncNow() async => nudges++;
}
