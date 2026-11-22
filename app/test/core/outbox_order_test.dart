import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/sync/outbox.dart';

/// **What was created first goes out first** — also within one second. `createdAt`
/// holds whole seconds, so the order inside one used to be left to SQLite; the id, a
/// UUIDv7, decides now — and within one millisecond, the ids follow each other.
void main() {
  late HiwiskiDatabase db;

  setUp(() => db = HiwiskiDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('entries of the same second go out in the order of their ids', () async {
    final second = DateTime(2026, 10, 23, 9);
    // Inserted in the opposite order of their ids: the list's create has the
    // smaller id, the task's update the larger one.
    for (final (id, entity) in [('0002', 'task'), ('0001', 'list')]) {
      await db
          .into(db.outboxEntries)
          .insert(
            OutboxEntriesCompanion.insert(
              mutationId: id,
              entityType: EntityTypes.todo,
              entityId: entity,
              op: SyncOps.upsert,
              createdAt: second,
            ),
          );
    }

    final pending = await Outbox(db).pending();

    expect(pending.map((entry) => entry.entityId), equals(['list', 'task']));
  });

  test(
    'entries of the same millisecond go out in the order they were written',
    () async {
      final outbox = Outbox(db);
      final written = [for (var i = 0; i < 40; i++) 'item$i'];
      await withClock(Clock.fixed(DateTime(2026, 11, 21, 9)), () async {
        for (final id in written) {
          await outbox.add(
            entityType: EntityTypes.mindmapNode,
            entityId: id,
            op: SyncOps.upsert,
          );
        }
      });

      final pending = await outbox.pending();

      expect(pending.map((entry) => entry.entityId), equals(written));
      expect(
        pending.map((entry) => entry.mutationId),
        everyElement(matches(_uuidV7)),
      );
    },
  );
}

final _uuidV7 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
