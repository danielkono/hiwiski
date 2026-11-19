import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../common/ids.dart';
import '../common/wire.dart';
import '../db/hiwiski_database.dart';
import '../db/tables.dart';
import 'entity_codec.dart';

/// The outbox of a device used without a server, and what becomes of it when the
/// device connects to one.
///
/// Without a server every change still goes through [LocalWrites] and into the
/// outbox — it is simply never sent. When the device connects, that outbox **is**
/// the migration: compacted to one creation per item, it goes out through the
/// ordinary push, with its idempotency keys, its retries and its visible rejections.
/// There is no second way of turning rows into fields that could drift from the one
/// every change already takes.
class LocalTakeover {
  LocalTakeover(this._db);

  final HiwiskiDatabase _db;

  /// How long something deleted without a server stays restorable — the server's
  /// default for its trash.
  static const trashRetention = Duration(days: 30);

  static const _tablePlaceholder = '{table}';
  static const _columnPlaceholder = '{column}';

  /// Every occurrence of one id in a text column replaced by another. A UUID occurs
  /// nowhere by chance, so a column's value — an owner, a JSON list of assignees, a
  /// mutation's fields — is rewritten exactly where it names the member.
  static const _replaceId =
      'UPDATE "$_tablePlaceholder" '
      'SET "$_columnPlaceholder" = REPLACE("$_columnPlaceholder", ?1, ?2) '
      'WHERE instr("$_columnPlaceholder", ?1) > 0';

  /// The order of a migration: containers before what they contain, so that the
  /// server finds every container when its content arrives. Types not named here go
  /// last.
  static const _rank = {
    EntityTypes.tag: 0,
    EntityTypes.calendar: 0,
    EntityTypes.todoList: 0,
    EntityTypes.board: 0,
    EntityTypes.calendarSubscription: 1,
    EntityTypes.calendarFeed: 1,
    EntityTypes.wikiPage: 2,
    EntityTypes.todo: 3,
    EntityTypes.event: 3,
    EntityTypes.widget: 3,
    EntityTypes.todoOccurrence: 4,
    EntityTypes.comment: 5,
    EntityTypes.listOrder: 6,
  };

  /// Where [type] goes in an order of creations: containers before what they hold.
  static int rankOf(String type) => _rank[type] ?? _rank.length;

  /// One mutation per item instead of every change ever made to it.
  ///
  /// - Every change of an item becomes **one** upsert carrying the fields as they are
  ///   now: the first change brought all of them, every later one only what it changed,
  ///   so merged in order they are the item's current state.
  /// - An item deleted since — itself or along with its container — goes, mutations
  ///   and all, if the server never knew it. Its row stays, for the trash, until
  ///   [deletedBefore].
  /// - The order is rebuilt: containers first, a page after its parent page.
  ///
  /// Run on every start without a server, the outbox stays about as large as the data;
  /// run before connecting, it is what goes out. Entries that are not simply waiting —
  /// rejected, blocked, parked — are left as they are: a device without a server has
  /// none, and on any other they are the member's to decide.
  Future<void> compact({required DateTime deletedBefore}) => _db.transaction(
    () async {
      await _purgeDeleted(before: deletedBefore);
      final entries =
          await (_db.select(_db.outboxEntries)..orderBy([
                (entry) => OrderingTerm.asc(entry.createdAt),
                (entry) => OrderingTerm.asc(entry.mutationId),
              ]))
              .get();
      final byItem = <(String, String), List<OutboxRow>>{};
      for (final entry in entries) {
        byItem
            .putIfAbsent((entry.entityType, entry.entityId), () => [])
            .add(entry);
      }

      final merged = <_Merged>[];
      final replaced = <String>[];
      final gone = <String>{};
      for (final MapEntry(key: (type, id), value: changes) in byItem.entries) {
        if (changes.any((entry) => entry.state != OutboxStates.pending)) {
          continue;
        }
        final item = await _merge(type, id, changes);
        replaced.addAll([for (final entry in changes) entry.mutationId]);
        if (item == null) {
          gone.add(id);
        } else {
          merged.add(item);
        }
      }
      if (replaced.isEmpty) return;

      await (_db.delete(
        _db.outboxEntries,
      )..where((entry) => entry.mutationId.isIn(replaced))).go();
      await _insertInOrder(_withoutOrphans(merged, gone));
    },
  );

  /// Rewrites the member [from] to [to] everywhere on the device: owners, creators,
  /// assignees, attendees, the member's own list order, and every field still
  /// waiting in the outbox.
  ///
  /// For a device that connects by signing in to an account the server already has:
  /// the member made without a server becomes that account.
  Future<void> rewriteMember(String from, String to) =>
      _db.transaction(() async {
        for (final table in _db.allTables) {
          for (final column in table.$columns) {
            if (column.type != DriftSqlType.string) continue;
            await _db.customUpdate(
              _replaceId
                  .replaceAll(_tablePlaceholder, table.actualTableName)
                  .replaceAll(_columnPlaceholder, column.name),
              variables: [Variable(from), Variable(to)],
              updates: {table},
            );
          }
        }
      });

  /// What an account the server already has keeps over the device's own: its order
  /// of the task lists, of which there is one per member. The device's would only
  /// collide with it.
  Future<void> yieldToExistingAccount() => (_db.delete(
    _db.outboxEntries,
  )..where((entry) => entry.entityType.equals(EntityTypes.listOrder))).go();

  /// Throws away for good what was deleted before [before] — on the server the
  /// retention period does the same.
  Future<void> _purgeDeleted({required DateTime before}) async {
    for (final codec in entityCodecs) {
      final info = codec.table(_db);
      final row = info as SyncedItem;
      final ids =
          await (_db.selectOnly(info)
                ..addColumns([row.id])
                ..where(row.deletedAt.isSmallerThanValue(before)))
              .map((result) => result.read(row.id))
              .get();
      for (final id in ids) {
        if (id != null) await codec.purge(_db, id);
      }
    }
  }

  /// [changes] of one item as one mutation; `null` if nothing is left to send.
  Future<_Merged?> _merge(
    String type,
    String id,
    List<OutboxRow> changes,
  ) async {
    if (changes case []) return null;
    final first = changes[0];
    final codec = entityCodecs.where((codec) => codec.entityType == type);
    final state = codec.isEmpty ? null : await _rowState(codec.first, id);
    final gone = state == null || state.deleted;
    if (gone) {
      // Never on the server: there is nothing to delete there either.
      if (first.baseVersion == null) return null;
      return _Merged(
        type: type,
        id: id,
        op: SyncOps.delete,
        fields: const {},
        baseVersion: first.baseVersion,
        containerType: null,
        containerId: null,
        label: changes.lastOrNull?.label ?? first.label,
        firstCreated: first.createdAt,
      );
    }
    final fields = <String, dynamic>{};
    String? containerType;
    String? containerId;
    String? label;
    for (final change in changes) {
      // A delete followed by changes is an item restored from the trash.
      if (change.op != SyncOps.upsert) continue;
      fields.addAll(jsonDecode(change.fields) as Map<String, dynamic>);
      containerType = change.containerType ?? containerType;
      containerId = change.containerId ?? containerId;
      label = change.label ?? label;
    }
    return _Merged(
      type: type,
      id: id,
      op: SyncOps.upsert,
      fields: fields,
      baseVersion: first.baseVersion,
      containerType: containerType,
      containerId: containerId,
      label: label,
      firstCreated: first.createdAt,
    );
  }

  /// [merged] without what sits in a container that went: the server never knew the
  /// container, so it would refuse what is in it. Deleting a list leaves its tasks'
  /// rows alone on the device — the server deletes those along with it — and without
  /// a server nothing ever did.
  static List<_Merged> _withoutOrphans(List<_Merged> merged, Set<String> gone) {
    final left = [...merged];
    bool dropped = true;
    while (dropped) {
      dropped = false;
      left.removeWhere((item) {
        final orphan = gone.contains(item.containerId);
        if (orphan) {
          gone.add(item.id);
          dropped = true;
        }
        return orphan;
      });
    }
    return left;
  }

  /// Whether the row of [id] exists and whether it is deleted; `null` if there is
  /// none.
  Future<({bool deleted})?> _rowState(EntityCodec codec, String id) async {
    final info = codec.table(_db);
    final row = info as SyncedItem;
    final result =
        await (_db.selectOnly(info)
              ..addColumns([row.deletedAt])
              ..where(row.id.equals(id)))
            .getSingleOrNull();
    if (result == null) return null;
    return (deleted: result.read(row.deletedAt) != null);
  }

  /// Writes [merged] back in the order the server needs, each waiting on its
  /// container's mutation.
  Future<void> _insertInOrder(List<_Merged> merged) async {
    final byId = {for (final item in merged) item.id: item};

    int depth(_Merged item, Set<String> seen) {
      final parent = byId[item.containerId];
      if (parent == null || parent.type != item.type || !seen.add(item.id)) {
        return 0;
      }
      return depth(parent, seen) + 1;
    }

    final depths = {for (final item in merged) item.id: depth(item, {})};
    final ordered = [...merged]
      ..sort((a, b) {
        final byRank = (_rank[a.type] ?? _rank.length).compareTo(
          _rank[b.type] ?? _rank.length,
        );
        if (byRank != 0) return byRank;
        final byDepth = depths[a.id]!.compareTo(depths[b.id]!);
        if (byDepth != 0) return byDepth;
        return a.firstCreated.compareTo(b.firstCreated);
      });

    // `createdAt` holds whole seconds and decides the order: one second apart, ending
    // now, so nothing waits in the future and nothing written later comes before them.
    final start = clock.now().subtract(Duration(seconds: ordered.length));
    final mutations = <String, String>{};
    for (final (index, item) in ordered.indexed) {
      final mutationId = newId();
      mutations[item.id] = mutationId;
      await _db
          .into(_db.outboxEntries)
          .insert(
            OutboxRow(
              mutationId: mutationId,
              entityType: item.type,
              entityId: item.id,
              containerType: item.containerType,
              containerId: item.containerId,
              op: item.op,
              fields: jsonEncode(item.fields),
              baseVersion: item.baseVersion,
              dependsOn: item.containerId == null
                  ? null
                  : mutations[item.containerId],
              state: OutboxStates.pending,
              attempts: 0,
              createdAt: start.add(Duration(seconds: index)),
              label: item.label,
            ),
          );
    }
  }
}

/// One item's changes, merged into one mutation.
final class _Merged({
  required final String type,
  required final String id,
  required final String op,
  required final Map<String, dynamic> fields,
  required final int? baseVersion,
  required final String? containerType,
  required final String? containerId,
  required final String? label,

  /// When the item's first change was made — the order among items of one kind.
  required final DateTime firstCreated,
});
