import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../common/ids.dart' as ids;
import '../db/hiwiski_database.dart';
import '../common/sync_limits.dart';
import '../common/wire.dart';
import '../db/tables.dart';

/// The local queue.
///
/// Every mutation carries a client-generated `mutationId` as an idempotency key —
/// otherwise retries after a dropped connection create things twice.
/// What a change waiting in the outbox is for.
typedef OutboxTarget = ({
  String entityType,
  String entityId,
  String? containerType,
  String? containerId,
});

class Outbox {
  Outbox(this._db);

  final HiwiskiDatabase _db;

  /// The entries that wait for the user: they no longer go out on their own.
  static const _stuck = [OutboxStates.rejected, OutboxStates.blocked];

  static const _countAttempt =
      'UPDATE outbox_entries SET attempts = attempts + 1 WHERE mutation_id = ?';

  /// A new id — see [ids.newId].
  static String newId() => ids.newId();

  /// Stores a mutation.
  ///
  /// [dependsOn] is the `mutationId` that has to go through first — the list created
  /// offline under the task created offline. If it fails permanently, the dependent
  /// ones must not run.
  Future<String> add({
    required String entityType,
    required String entityId,
    required String op,
    Map<String, dynamic> fields = const {},
    String? containerType,
    String? containerId,
    int? baseVersion,
    String? dependsOn,
    String? label,
  }) async {
    final mutationId = newId();
    await _db
        .into(_db.outboxEntries)
        .insert(
          OutboxRow(
            mutationId: mutationId,
            entityType: entityType,
            entityId: entityId,
            containerType: containerType,
            containerId: containerId,
            op: op,
            fields: jsonEncode(fields),
            baseVersion: baseVersion,
            dependsOn: dependsOn,
            state: OutboxStates.pending,
            attempts: 0,
            createdAt: clock.now(),
            label: label,
          ),
        );
    return mutationId;
  }

  /// What goes out next — in the order it was created.
  ///
  /// Blocked and rejected entries stay put: they appear in the visible list until the
  /// user decides.
  Future<List<OutboxRow>> pending({int limit = 50}) {
    return (_db.select(_db.outboxEntries)
          ..where((entry) => entry.state.equals(OutboxStates.pending))
          // `createdAt` holds whole seconds: within one, the id decides — a UUIDv7,
          // ordered to the millisecond. Ties were left to SQLite, which keeps insert
          // order in practice but does not promise it.
          ..orderBy([
            (entry) => OrderingTerm.asc(entry.createdAt),
            (entry) => OrderingTerm.asc(entry.mutationId),
          ])
          ..limit(limit))
        .get();
  }

  /// The items and containers changes still wait for. A home screen widget keeps the
  /// device's own picture of a list while one of these is for it: the server's answer
  /// would not have the change yet.
  Future<List<OutboxTarget>> pendingTargets() async => [
    for (final row in await (_db.select(
      _db.outboxEntries,
    )..where((entry) => entry.state.equals(OutboxStates.pending))).get())
      (
        entityType: row.entityType,
        entityId: row.entityId,
        containerType: row.containerType,
        containerId: row.containerId,
      ),
  ];

  /// Whether a run could still get anything out: an entry waiting, or one parked
  /// until the next pull brings its board.
  Future<bool> holdsOutgoing() async {
    final entry =
        await (_db.select(_db.outboxEntries)
              ..where(
                (entry) => entry.state.isIn(const [
                  OutboxStates.pending,
                  OutboxStates.parked,
                ]),
              )
              ..limit(1))
            .getSingleOrNull();
    return entry != null;
  }

  Stream<int> watchPendingCount() {
    final query = _db.selectOnly(_db.outboxEntries)
      ..addColumns([_db.outboxEntries.mutationId.count()])
      ..where(_db.outboxEntries.state.equals(OutboxStates.pending));
    return query
        .map((row) => row.read(_db.outboxEntries.mutationId.count()) ?? 0)
        .watchSingle();
  }

  /// Everything that is stuck — for the visible list.
  ///
  /// "Plan vacation and 3 more changes could not be applied."
  /// [Try again] [View] [Discard]
  Stream<List<OutboxRow>> watchStuck() {
    return (_db.select(_db.outboxEntries)
          ..where((entry) => entry.state.isIn(_stuck))
          ..orderBy([
            (entry) => OrderingTerm.asc(entry.createdAt),
            (entry) => OrderingTerm.asc(entry.mutationId),
          ]))
        .watch();
  }

  Future<void> remove(String mutationId) => (_db.delete(
    _db.outboxEntries,
  )..where((entry) => entry.mutationId.equals(mutationId))).go();

  /// A `rejected` blocks the whole chain and appears to the user **as a group**.
  Future<void> reject(String mutationId, String? code) async {
    await _db.transaction(() async {
      await (_db.update(
        _db.outboxEntries,
      )..where((entry) => entry.mutationId.equals(mutationId))).write(
        OutboxEntriesCompanion(
          state: const Value(OutboxStates.rejected),
          errorCode: Value(code),
        ),
      );
      await _blockDependents(mutationId);
    });
  }

  Future<void> _blockDependents(String mutationId) async {
    final dependents = await (_db.select(
      _db.outboxEntries,
    )..where((entry) => entry.dependsOn.equals(mutationId))).get();
    for (final dependent in dependents) {
      await (_db.update(
        _db.outboxEntries,
      )..where((entry) => entry.mutationId.equals(dependent.mutationId))).write(
        const OutboxEntriesCompanion(state: Value(OutboxStates.blocked)),
      );
      await _blockDependents(dependent.mutationId);
    }
  }

  // --- Held: a value beyond the server's limit --------------------------------------

  /// Holds [mutationId] back: a value in it is beyond the server's limit
  /// ([SyncLimits]). It shows with the changes that cannot be synced, under
  /// `sync.value_too_large`, and what depends on it waits — the same as a rejection,
  /// only decided on the device, so the change itself stays where it was written.
  Future<void> hold(String mutationId) =>
      reject(mutationId, SyncLimits.valueTooLarge);

  /// [mutationId] waits for an entry that cannot go out yet.
  Future<void> block(String mutationId) =>
      (_db.update(
        _db.outboxEntries,
      )..where((entry) => entry.mutationId.equals(mutationId))).write(
        const OutboxEntriesCompanion(state: Value(OutboxStates.blocked)),
      );

  bool _isHeld(OutboxRow entry) =>
      entry.state == OutboxStates.rejected &&
      entry.errorCode == SyncLimits.valueTooLarge;

  /// A new change of [entityId] takes over [fields] from the held entries of the
  /// item, or all of them for a delete ([everything]): the newer value is the one
  /// that counts. A held entry left with nothing goes; one whose remaining values fit
  /// again goes out after all. Either way, what waited for it waits no longer.
  ///
  /// So shortening a page that was too long syncs it — the held entry does not stay
  /// behind with the old, longer text.
  Future<void> supersedeHeld(
    String entityId,
    Iterable<String> fields, {
    bool everything = false,
  }) async {
    final held = await (_db.select(
      _db.outboxEntries,
    )..where((entry) => entry.entityId.equals(entityId))).get();
    final taken = fields.toSet();
    for (final entry in held.where(_isHeld)) {
      final remaining = everything
          ? const <String, dynamic>{}
          : {
              for (final MapEntry(:key, :value)
                  in (jsonDecode(entry.fields) as Map<String, dynamic>).entries)
                if (!taken.contains(key)) key: value,
            };
      if (remaining.isEmpty && entry.op != SyncOps.delete) {
        await _drop(entry);
      } else if (SyncLimits.exceeded(remaining) == null) {
        await (_db.update(
          _db.outboxEntries,
        )..where((row) => row.mutationId.equals(entry.mutationId))).write(
          OutboxEntriesCompanion(
            fields: Value(jsonEncode(remaining)),
            state: const Value(OutboxStates.pending),
            errorCode: const Value(null),
          ),
        );
        await _release(entry.mutationId);
      } else {
        await (_db.update(
          _db.outboxEntries,
        )..where((row) => row.mutationId.equals(entry.mutationId))).write(
          OutboxEntriesCompanion(fields: Value(jsonEncode(remaining))),
        );
      }
    }
  }

  /// Whether a new entry hanging off [dependsOn] has to wait: its prerequisite is
  /// held back as a new item (the server does not know the item yet), or waits
  /// itself.
  Future<bool> waitsOn(String? dependsOn) async {
    if (dependsOn == null) return false;
    final parent = await (_db.select(
      _db.outboxEntries,
    )..where((entry) => entry.mutationId.equals(dependsOn))).getSingleOrNull();
    if (parent == null) return false;
    return parent.state == OutboxStates.blocked ||
        (_isHeld(parent) &&
            parent.op == SyncOps.upsert &&
            parent.baseVersion == null);
  }

  /// Removes a held entry; what depended on it now depends on what it depended on,
  /// and goes out again unless that one is stuck as well.
  Future<void> _drop(OutboxRow entry) async {
    final dependents = await (_db.select(
      _db.outboxEntries,
    )..where((row) => row.dependsOn.equals(entry.mutationId))).get();
    await (_db.update(_db.outboxEntries)
          ..where((row) => row.dependsOn.equals(entry.mutationId)))
        .write(OutboxEntriesCompanion(dependsOn: Value(entry.dependsOn)));
    await remove(entry.mutationId);
    final dependsOn = entry.dependsOn;
    final parent = dependsOn == null
        ? null
        : await (_db.select(_db.outboxEntries)
                ..where((row) => row.mutationId.equals(dependsOn)))
              .getSingleOrNull();
    if (parent != null && _stuck.contains(parent.state)) return;
    for (final dependent in dependents) {
      if (dependent.state != OutboxStates.blocked) continue;
      await _unblock(dependent.mutationId);
    }
  }

  /// The blocked entries below [mutationId] go out again.
  Future<void> _release(String mutationId) async {
    final dependents =
        await (_db.select(_db.outboxEntries)..where(
              (entry) =>
                  entry.dependsOn.equals(mutationId) &
                  entry.state.equals(OutboxStates.blocked),
            ))
            .get();
    for (final dependent in dependents) {
      await _unblock(dependent.mutationId);
    }
  }

  Future<void> _unblock(String mutationId) async {
    await (_db.update(
      _db.outboxEntries,
    )..where((row) => row.mutationId.equals(mutationId))).write(
      const OutboxEntriesCompanion(state: Value(OutboxStates.pending)),
    );
    await _release(mutationId);
  }

  /// Temporary errors keep running with backoff and show nothing — an unreachable
  /// server is not an error on the go but everyday life.
  Future<void> countAttempt(String mutationId) async {
    await _db.customStatement(_countAttempt, [mutationId]);
  }

  /// "Try again" on the visible list.
  Future<void> retryAll() =>
      (_db.update(
        _db.outboxEntries,
      )..where((entry) => entry.state.isIn(_stuck))).write(
        const OutboxEntriesCompanion(
          state: Value(OutboxStates.pending),
          errorCode: Value(null),
          attempts: Value(0),
        ),
      );

  /// "Discard" — the user has seen the list and decided.
  Future<void> discardStuck() => (_db.delete(
    _db.outboxEntries,
  )..where((entry) => entry.state.isIn(_stuck))).go();

  /// The last still-open mutation for this item — the new one hangs off it.
  Future<String?> lastPendingFor(String entityId) async {
    final row =
        await (_db.select(_db.outboxEntries)
              ..where((entry) => entry.entityId.equals(entityId))
              ..orderBy([
                (entry) => OrderingTerm.desc(entry.createdAt),
                (entry) => OrderingTerm.desc(entry.mutationId),
              ])
              ..limit(1))
            .getSingleOrNull();
    return row?.mutationId;
  }
}
