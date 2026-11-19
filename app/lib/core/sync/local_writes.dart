import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../common/wire.dart';
import '../db/hiwiski_database.dart';
import '../db/tables.dart';
import 'entity_codec.dart';
import 'outbox.dart';
import '../common/sync_limits.dart';
import 'sync_engine.dart';

/// **The only way a change made on this device gets into a synced table.**
///
/// The local database and the outbox must not drift apart: a row written without its
/// mutation never reaches the server — no error, no banner, it is simply never
/// synced, and the next pulled change to the item overwrites it. So a
/// repository does not write synced rows itself. It hands each one to a [LocalWrite]
/// together with what goes out, and the row and its outbox entry are written in one
/// transaction — both or neither. `synced_writes` (tool/hiwiski_lints) reports every
/// other write to a synced table outside the sync layer.
///
/// What the server sends lands through the sync itself ([SyncEngine], the
/// [EntityCodec]s), not through here.
class LocalWrites {
  LocalWrites({required this._db, required this._outbox, required this._sync});

  final HiwiskiDatabase _db;
  final Outbox _outbox;
  final SyncTrigger _sync;

  /// Runs [body] in one transaction and nudges the sync once it is committed.
  ///
  /// Reads that the writes depend on (the end of a list, the row as it is now) belong
  /// inside [body]: nothing gets in between them and the write. The [LocalWrite] is
  /// valid only while [body] runs.
  Future<T> run<T>(Future<T> Function(LocalWrite write) body) async {
    final write = LocalWrite._(_db, _outbox);
    final T result;
    try {
      result = await _db.transaction(() => body(write));
    } finally {
      write._open = false;
    }
    // **After** the commit: the sync reads the outbox itself, and a query inside an
    // open transaction waits for it to end.
    if (write._queued) {
      // The sync reports its own failures: banner, retry.
      _sync.syncNow().ignore();
    }
    return result;
  }
}

/// One mutation in the outbox, written by a [LocalWrite] — what a [LocalWrite.cascade]
/// follows from.
final class Queued {
  Queued._(this._write, this.mutationId);

  final LocalWrite _write;

  final String mutationId;
}

/// The writes of one [LocalWrites.run]: each row together with its mutation.
final class LocalWrite {
  LocalWrite._(this._db, this._outbox);

  final HiwiskiDatabase _db;
  final Outbox _outbox;

  bool _open = true;
  bool _queued = false;

  /// Inserts a new item and queues its creation.
  ///
  /// The id comes from [row]. [after] is the item whose still-pending mutation this
  /// one waits for: the task created offline in a list created offline must not go
  /// out if the list fails permanently.
  Future<Queued> create<T extends SyncedItem, D>(
    TableInfo<T, D> table,
    Insertable<D> row, {
    required Map<String, dynamic> fields,
    String? containerType,
    String? containerId,
    String? after,
    required String label,
  }) async {
    _ensureOpen();
    final id = switch (row.toColumns(false)[_idColumn]) {
      Variable<String>(:final String value) => value,
      _ => throw ArgumentError.value(row, 'row', 'has no id'),
    };
    await _db.into(table).insert(row);
    return _queue(
      table,
      id: id,
      op: SyncOps.upsert,
      fields: fields,
      containerType: containerType,
      containerId: containerId,
      baseVersion: null,
      dependsOn: after == null ? null : await _outbox.lastPendingFor(after),
      label: label,
    );
  }

  /// Writes [row] onto the item [id] and queues [fields] — only what changed: whoever
  /// checks off while someone else moves the due date loses nothing.
  ///
  /// [version] is the one the change builds on — the item as the member saw it.
  Future<Queued> change<T extends SyncedItem, D>(
    TableInfo<T, D> table,
    Insertable<D> row, {
    required String id,
    required int version,
    required Map<String, dynamic> fields,
    String? containerType,
    String? containerId,
    required String label,
  }) async {
    _ensureOpen();
    if (row.toColumns(false)[_idColumn] case Variable<String>(:final value)
        when value != id) {
      throw ArgumentError.value(row, 'row', 'belongs to $value, not to $id');
    }
    await (_db.update(table)..where((item) => item.id.equals(id))).write(row);
    // The newer value counts: a held entry of the item gives up what this one
    // writes again — shortened, the page syncs.
    await _outbox.supersedeHeld(id, fields.keys);
    return _queue(
      table,
      id: id,
      op: SyncOps.upsert,
      fields: fields,
      containerType: containerType,
      containerId: containerId,
      baseVersion: version,
      dependsOn: await _outbox.lastPendingFor(id),
      label: label,
    );
  }

  /// Soft delete, locally and as a mutation: the tombstone carries it.
  ///
  /// [at] is the moment it is deleted — given when rows deleted along with it
  /// ([cascade]) should carry the same one.
  Future<Queued> delete<T extends SyncedItem, D>(
    TableInfo<T, D> table, {
    required String id,
    required int version,
    required String label,
    DateTime? at,
  }) async {
    _ensureOpen();
    final deletedAt = table.asDslTable.deletedAt as GeneratedColumn<DateTime>;
    await (_db.update(table)..where((item) => item.id.equals(id))).write(
      RawValuesInsertable({deletedAt.name: Variable(at ?? clock.now())}),
    );
    await _outbox.supersedeHeld(id, const [], everything: true);
    return _queue(
      table,
      id: id,
      op: SyncOps.delete,
      fields: const {},
      containerType: null,
      containerId: null,
      baseVersion: version,
      dependsOn: await _outbox.lastPendingFor(id),
      label: label,
    );
  }

  /// Writes [row] onto the rows [where] picks, **without a mutation of their own**:
  /// they follow from [cause], and the server does the same when it applies it — the
  /// events of a deleted calendar, the pages below a deleted one. Locally right away,
  /// or they would stay on screen until the server reports them back.
  ///
  /// [cause] must come from this same run.
  Future<void> cascade<T extends SyncedItem, D>(
    Queued cause,
    TableInfo<T, D> table,
    Insertable<D> row, {
    required Expression<bool> Function(T item) where,
  }) async {
    _ensureOpen();
    if (!identical(cause._write, this)) {
      throw ArgumentError.value(cause, 'cause', 'was queued in another run');
    }
    await (_db.update(table)..where(where)).write(row);
  }

  Future<Queued> _queue(
    TableInfo<Table, Object?> table, {
    required String id,
    required String op,
    required Map<String, dynamic> fields,
    required String? containerType,
    required String? containerId,
    required int? baseVersion,
    required String? dependsOn,
    required String label,
  }) async {
    final mutationId = await _outbox.add(
      entityType: _entityTypeOf(table),
      entityId: id,
      op: op,
      fields: fields,
      containerType: containerType,
      containerId: containerId,
      baseVersion: baseVersion == 0 ? null : baseVersion,
      dependsOn: dependsOn,
      label: label,
    );
    if (SyncLimits.exceeded(fields) != null) {
      // Written on the device all the same — nothing typed is lost — but held back
      // until a later change brings the value within the server's limit.
      await _outbox.hold(mutationId);
    } else if (await _outbox.waitsOn(dependsOn)) {
      await _outbox.block(mutationId);
    }
    _queued = true;
    return Queued._(this, mutationId);
  }

  /// The entity type the server knows the table by — from the codec the sync applies
  /// its changes with, so what goes out and what comes back are the same type.
  String _entityTypeOf(TableInfo<Table, Object?> table) {
    for (final codec in entityCodecs) {
      if (codec.table(_db).actualTableName == table.actualTableName) {
        return codec.entityType;
      }
    }
    throw ArgumentError.value(
      table.actualTableName,
      'table',
      'is synced by no codec',
    );
  }

  void _ensureOpen() {
    if (!_open) {
      throw StateError('A LocalWrite is used only inside its LocalWrites.run.');
    }
  }
}

const _idColumn = 'id';
