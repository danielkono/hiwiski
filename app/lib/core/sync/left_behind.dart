import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../common/ids.dart';
import '../common/wire.dart';
import '../db/hiwiski_database.dart';
import '../db/tables.dart';
import 'entity_codec.dart';
import 'local_takeover.dart';

/// **What a backup restore left behind on this device**.
///
/// A restore puts the server back to the archive's state. A device that saw more —
/// a task created since, a list renamed since — threw that away with its mirror, and
/// after a server that died with a week-old backup, the week was gone from every
/// phone too. Now the device keeps a copy before its mirror goes ([capture]), and
/// once the restored server's state is in, keeps of it what the server does not have
/// or has older ([settle]). The member is told and brings it back ([restore]) — or
/// lets it go ([discard]).
///
/// What the device had not sent yet is not here: the outbox goes out by itself, as
/// always.
class LeftBehind {
  LeftBehind(this._db, {this._codecs = entityCodecs});

  final HiwiskiDatabase _db;
  final List<EntityCodec> _codecs;

  /// Every mirrored row as it would go out — before a restore's discard takes them.
  /// Rows waiting in the outbox stay out: their change goes out by itself.
  Future<void> capture() => _db.transaction(() async {
    final queued = {
      for (final entry in await _db.select(_db.outboxEntries).get())
        (entry.entityType, entry.entityId),
    };
    final now = clock.now();
    for (final codec in _codecs) {
      final table = codec.table(_db);
      // Every synced table mixes in [SyncedItem]; its columns are the generated ones.
      final id = (table as SyncedItem).id;
      final ids = await (_db.selectOnly(
        table,
      )..addColumns([id])).map((row) => row.read(id)).get();
      for (final itemId in ids.nonNulls) {
        if (queued.contains((codec.entityType, itemId))) continue;
        final item = await codec.stored(_db, itemId);
        // Never on the server: nothing a restore could have taken.
        if (item == null || item.version == 0) continue;
        await _db
            .into(_db.leftBehindItems)
            .insertOnConflictUpdate(
              LeftBehindItemsCompanion.insert(
                entityType: codec.entityType,
                entityId: itemId,
                ownerId: item.ownerId,
                version: item.version,
                deleted: Value(item.deleted),
                containerId: Value(item.containerId),
                entityKey: Value(item.entityKey),
                fields: Value(jsonEncode(item.fields)),
                label: Value(item.label),
                leftAt: now,
              ),
            );
      }
    }
  });

  /// Keeps of the copy what the restored server does not have, or has older; lets go
  /// of what it has as it was. After the restored state is complete on the device.
  Future<void> settle() => _db.transaction(() async {
    final open = await (_db.select(
      _db.leftBehindItems,
    )..where((row) => row.settled.equals(false))).get();
    for (final left in open) {
      final codec = _codec(left.entityType);
      final now = codec == null ? null : await codec.stored(_db, left.entityId);
      final keep = switch (now) {
        // Gone from the server: what was there comes back — but a deletion of
        // something the server does not have has nothing left to do.
        null => !left.deleted,
        // The server's is as new or newer: it kept what the device had.
        final server when server.version >= left.version => false,
        // Older on the server: the device saw more.
        _ => true,
      };
      if (keep) {
        await (_db.update(_db.leftBehindItems)..where(
              (item) =>
                  item.entityType.equals(left.entityType) &
                  item.entityId.equals(left.entityId),
            ))
            .write(const LeftBehindItemsCompanion(settled: Value(true)));
      } else {
        await _forget(left);
      }
    }
  });

  /// What is left behind, for the member to decide on — settled only.
  Stream<List<LeftBehindRow>> watch() =>
      (_db.select(_db.leftBehindItems)
            ..where((row) => row.settled.equals(true))
            ..orderBy([(row) => OrderingTerm.asc(row.label)]))
          .watch();

  /// Brings [keys] back — every one if `null`: into the mirror as it was, and into the
  /// outbox, which takes it to the server like any change made here. Containers go
  /// first, a page after its parent page; a change to something the server has newer
  /// meanwhile is a conflict like any other.
  ///
  /// A pinboard's connection brings back with it its elements left behind too: the
  /// server refuses a connection to an element it does not have, and brought back
  /// alone, it was refused for good.
  Future<void> restore({
    Set<(String, String)>? keys,
  }) => _db.transaction(() async {
    final settled = await (_db.select(
      _db.leftBehindItems,
    )..where((row) => row.settled.equals(true))).get();
    final wanted = keys == null
        ? null
        : {
            ...keys,
            for (final row in settled)
              if (row.entityType == EntityTypes.pinboardEdge &&
                  keys.contains((row.entityType, row.entityId)))
                for (final end in _endsOf(row)) (EntityTypes.pinboardNode, end),
          };
    final rows = [
      for (final row in settled)
        if (wanted == null || wanted.contains((row.entityType, row.entityId)))
          row,
    ];
    final ordered = _ordered(rows);
    // One second apart, ending now: the outbox goes out by `createdAt`, in whole
    // seconds — so the containers do go first (as in LocalTakeover).
    final start = clock.now().subtract(Duration(seconds: ordered.length));
    final queued = <String, String>{};
    for (final (index, left) in ordered.indexed) {
      final codec = _codec(left.entityType);
      if (codec == null) continue;
      final serverVersion = await codec.localVersion(_db, left.entityId);
      final fields = (jsonDecode(left.fields) as Map).cast<String, dynamic>();
      if (left.deleted) {
        if (serverVersion != null) {
          await codec.markDeleted(_db, left.entityId, serverVersion);
        }
      } else {
        await codec.upsert(
          _db,
          id: left.entityId,
          ownerId: left.ownerId,
          version: serverVersion ?? 0,
          containerId: left.containerId,
          entityKey: left.entityKey,
          fields: fields,
        );
      }
      if (!left.deleted || serverVersion != null) {
        final mutationId = newId();
        queued[left.entityId] = mutationId;
        await _db
            .into(_db.outboxEntries)
            .insert(
              OutboxRow(
                mutationId: mutationId,
                entityType: left.entityType,
                entityId: left.entityId,
                containerType: _containerType(
                  left.entityType,
                  left.containerId,
                ),
                containerId: left.containerId,
                op: left.deleted ? SyncOps.delete : SyncOps.upsert,
                fields: left.deleted ? '{}' : left.fields,
                baseVersion: serverVersion,
                dependsOn: _after(left, queued),
                state: OutboxStates.pending,
                attempts: 0,
                createdAt: start.add(Duration(seconds: index)),
                label: left.label.isEmpty ? null : left.label,
              ),
            );
      }
      await _forget(left);
    }
  });

  /// Lets [keys] go — every one if `null`.
  Future<void> discard({Set<(String, String)>? keys}) =>
      _db.transaction(() async {
        for (final row in await _db.select(_db.leftBehindItems).get()) {
          if (keys == null || keys.contains((row.entityType, row.entityId))) {
            await _forget(row);
          }
        }
      });

  Future<void> _forget(LeftBehindRow row) =>
      (_db.delete(_db.leftBehindItems)..where(
            (item) =>
                item.entityType.equals(row.entityType) &
                item.entityId.equals(row.entityId),
          ))
          .go();

  /// The elements a connection's copy joins.
  static Set<String> _endsOf(LeftBehindRow row) => switch (jsonDecode(
    row.fields,
  )) {
    {WireFields.fromId: final String from, WireFields.toId: final String to} =>
      {from, to},
    _ => const {},
  };

  /// The mutation brought back before [left] that it waits for: a connection's
  /// elements brought back with it — the later of the two, which goes after the
  /// other — or else its container.
  static String? _after(LeftBehindRow left, Map<String, String> queued) {
    if (left.entityType == EntityTypes.pinboardEdge) {
      final ends = _endsOf(left);
      final end = queued.keys.where(ends.contains).lastOrNull;
      if (end != null) return queued[end];
    }
    return left.containerId == null ? null : queued[left.containerId];
  }

  EntityCodec? _codec(String type) =>
      _codecs.where((codec) => codec.entityType == type).firstOrNull;

  /// The type of the container an item lies in, as the push names it.
  static String? _containerType(String type, String? containerId) =>
      containerId == null
      ? null
      : switch (type) {
          EntityTypes.todo => EntityTypes.todoList,
          EntityTypes.event ||
          EntityTypes.calendarSubscription => EntityTypes.calendar,
          EntityTypes.wikiPage ||
          EntityTypes.pinboardNode ||
          EntityTypes.pinboardEdge => EntityTypes.wikiPage,
          EntityTypes.widget => EntityTypes.board,
          _ => null,
        };

  /// Containers before what they hold, a page after its parent.
  static List<LeftBehindRow> _ordered(List<LeftBehindRow> rows) {
    final byId = {for (final row in rows) row.entityId: row};
    int depth(LeftBehindRow row, Set<String> seen) {
      final parent = byId[row.containerId];
      if (parent == null ||
          parent.entityType != row.entityType ||
          !seen.add(row.entityId)) {
        return 0;
      }
      return depth(parent, seen) + 1;
    }

    final depths = {for (final row in rows) row.entityId: depth(row, {})};
    return [...rows]..sort((a, b) {
      final byRank = LocalTakeover.rankOf(a.entityType)
          .compareTo(LocalTakeover.rankOf(b.entityType));
      if (byRank != 0) return byRank;
      return (depths[a.entityId] ?? 0).compareTo(depths[b.entityId] ?? 0);
    });
  }
}
