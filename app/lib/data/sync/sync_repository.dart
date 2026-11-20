import 'package:drift/drift.dart' show OrderingTerm;

import '../../core/db/hiwiski_database.dart';
import '../../core/sync/outbox.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_status.dart';
import '../../domain/sync/sync_items.dart';

/// Where the sync stands, and what the member decides about it: the conflicts nobody
/// has seen yet and the changes the server refused.
class SyncRepository {
  SyncRepository({
    required this._engine,
    required this._outbox,
    required this._db,
  });

  final SyncEngine _engine;
  final Outbox _outbox;
  final HiwiskiDatabase _db;

  SyncStatus get status => _engine.state;

  /// Every change of [status], from now on.
  Stream<SyncStatus> get statusChanges => _engine.changes;

  /// One run: out first, then in.
  Future<void> syncNow() => _engine.syncNow();

  /// The last run before signing out — after a background run under way.
  Future<void> syncLast() => _engine.syncLast();

  /// Ends the sync for whoever is leaving and waits until nothing runs any more.
  Future<void> stop() => _engine.stop();

  /// Hooks into the real-time stream and pulls on every signal.
  Future<void> listenForSignals() => _engine.listenForSignals();

  /// What waits to reach the server — it survives a restart: the changes in the
  /// outbox and the images kept on the device ([HiwiskiDatabase.watchUnsyncedCount]).
  /// Not the sync engine's count: that one decides when to push, and the images go
  /// up after every sync anyway.
  Stream<int> watchPendingCount() => _db.watchUnsyncedCount();

  /// The conflicts nobody has seen yet, oldest first.
  Stream<List<SyncConflict>> watchConflicts() =>
      (_db.select(_db.conflicts)
            ..orderBy([(row) => OrderingTerm.asc(row.detectedAt)]))
          .watch()
          .map((rows) => [for (final row in rows) row.toDomain()]);

  /// The changes the server refused, and those that wait on them.
  Stream<List<OutboxChange>> watchStuck() => _outbox.watchStuck().map(
    (rows) => [for (final row in rows) row.toDomain()],
  );

  /// "Apply anyway": the device's own discarded version goes out once more.
  Future<void> takeMine(SyncConflict conflict) =>
      _engine.takeMine(conflict.toRow());

  /// Seen, and the server state accepted.
  Future<void> dismissConflict(SyncConflict conflict) =>
      _engine.dismissConflict(conflict.toRow());

  /// Tries every stuck change once more.
  Future<void> retryStuck() async {
    await _outbox.retryAll();
    await _engine.syncNow();
  }

  /// What a backup restore left behind on this device, for the member to decide on.
  Stream<List<LeftBehindItem>> watchLeftBehind() =>
      _engine.leftBehind.watch().map(
        (rows) => [
          for (final row in rows)
            LeftBehindItem(
              entityType: row.entityType,
              entityId: row.entityId,
              label: row.label,
              deleted: row.deleted,
              leftAt: row.leftAt,
            ),
        ],
      );

  /// Brings [items] back to the server — every one if `null` — through the outbox,
  /// like any change made here.
  Future<void> restoreLeftBehind([List<LeftBehindItem>? items]) async {
    await _engine.leftBehind.restore(keys: _keys(items));
    await _engine.refreshCounts();
    // The sync reports its own failures: banner, retry.
    _engine.syncNow().ignore();
  }

  /// Lets [items] go — every one if `null`.
  Future<void> discardLeftBehind([List<LeftBehindItem>? items]) =>
      _engine.leftBehind.discard(keys: _keys(items));

  static Set<(String, String)>? _keys(List<LeftBehindItem>? items) =>
      items == null
      ? null
      : {for (final item in items) (item.entityType, item.entityId)};

  /// Gives the stuck changes up — and the message disappears at once.
  Future<void> discardStuck() async {
    await _outbox.discardStuck();
    await _engine.refreshCounts();
  }
}

extension on SyncConflict {
  ConflictRow toRow() => .new(
    id: id,
    entityType: entityType,
    entityId: entityId,
    field: field,
    mine: mine,
    theirs: theirs,
    base: base,
    detectedAt: detectedAt,
  );
}

extension on ConflictRow {
  SyncConflict toDomain() => .new(
    id: id,
    entityType: entityType,
    entityId: entityId,
    field: field,
    mine: mine,
    theirs: theirs,
    base: base,
    detectedAt: detectedAt,
  );
}

extension on OutboxRow {
  OutboxChange toDomain() => .new(
    mutationId: mutationId,
    entityType: entityType,
    entityId: entityId,
    containerType: containerType,
    containerId: containerId,
    op: op,
    fields: fields,
    baseVersion: baseVersion,
    dependsOn: dependsOn,
    state: state,
    errorCode: errorCode,
    attempts: attempts,
    createdAt: createdAt,
    label: label,
  );
}
