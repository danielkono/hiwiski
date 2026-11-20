import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/db/tables.dart';
import 'package:hiwiski/core/storage/local_image_store.dart';

/// **What has not reached the server counts as one**: the changes in the outbox and
/// the images kept on the device — both lost on signing out, so both named there.
void main() {
  late HiwiskiDatabase db;
  late LocalImageStore images;

  setUp(() {
    db = HiwiskiDatabase(NativeDatabase.memory());
    images = LocalImageStore(db);
  });

  tearDown(() => db.close());

  Future<void> change(String mutationId, {String? state}) => db
      .into(db.outboxEntries)
      .insert(
        OutboxEntriesCompanion.insert(
          mutationId: mutationId,
          entityType: EntityTypes.todo,
          entityId: 'task-$mutationId',
          op: SyncOps.upsert,
          createdAt: DateTime(2026, 11, 20),
          state: state == null ? const Value.absent() : Value(state),
        ),
      );

  Future<String> image() => images.put(
    ownerType: EntityTypes.todo,
    ownerItemId: 'task',
    bytes: Uint8List.fromList([1, 2, 3]),
    filename: 'a.jpg',
  );

  test('changes waiting and images kept are counted together', () async {
    await change('m1');
    await change('m2');
    // Refused: it waits on the member, not on the server — shown on its own.
    await change('m3', state: OutboxStates.rejected);
    await image();

    expect(await db.watchUnsyncedCount().first, equals(3));
  });

  test('the count follows images as they are kept and uploaded', () async {
    final counts = <int>[];
    final subscription = db.watchUnsyncedCount().listen(counts.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    final id = await image();
    await pumpEventQueue();
    await images.remove(id);
    await pumpEventQueue();

    expect(counts, equals([0, 1, 0]));
  });
}
