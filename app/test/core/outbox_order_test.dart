import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/sync/outbox.dart';

/// **What was created first goes out first** — also within one second. `createdAt`
/// holds whole seconds, so the order inside one used to be left to SQLite; the id, a
/// UUIDv7, decides now.
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
}
