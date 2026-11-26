import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../../core/api/generated/export.dart';
import '../../core/api/hiwiski_failure.dart';
import '../../core/common/wire.dart';
import '../../core/db/hiwiski_database.dart';
import '../../core/db/tables.dart';
import '../../core/sync/local_takeover.dart';
import '../../core/sync/local_writes.dart';

/// The trash of a device without a server.
///
/// On a server the trash is the retention period of the soft deletes;
/// here it is the same, on the device: what was deleted keeps its row with its
/// `deletedAt` until [LocalTakeover.trashRetention] has passed. It lists what the
/// server's would — lists, tasks, calendars, events, pages and tags — and, like the
/// server's, restores an item on its own, not what went with it — but for a page's
/// pinboard, which is in no trash of its own.
class LocalTrash {
  LocalTrash({required this._db, required this._writes});

  final HiwiskiDatabase _db;
  final LocalWrites _writes;

  static final _retentionDays = LocalTakeover.trashRetention.inDays;

  /// The trash, again whenever one of its tables changes.
  Stream<TrashList> watch() async* {
    yield await list();
    await for (final _ in _db.tableUpdates(
      TableUpdateQuery.onAllTables([
        _db.todoLists,
        _db.todos,
        _db.calendars,
        _db.events,
        _db.wikiPages,
        _db.tags,
      ]),
    )) {
      yield await list();
    }
  }

  Future<TrashList> list() async {
    final entries = <TrashEntry>[
      for (final row in await (_db.select(
        _db.todoLists,
      )..where((r) => r.deletedAt.isNotNull())).get())
        if (row.deletedAt case final at?)
          _entry(EntityTypes.todoList, row.id, row.name, at, row.ownerId),
      for (final row in await (_db.select(
        _db.todos,
      )..where((r) => r.deletedAt.isNotNull())).get())
        if (row.deletedAt case final at?)
          _entry(
            EntityTypes.todo,
            row.id,
            row.title,
            at,
            row.ownerId,
            restorable: await _alive(_db.todoLists, row.listId),
          ),
      for (final row in await (_db.select(
        _db.calendars,
      )..where((r) => r.deletedAt.isNotNull())).get())
        if (row.deletedAt case final at?)
          _entry(EntityTypes.calendar, row.id, row.name, at, row.ownerId),
      for (final row in await (_db.select(
        _db.events,
      )..where((r) => r.deletedAt.isNotNull())).get())
        if (row.deletedAt case final at?)
          _entry(
            EntityTypes.event,
            row.id,
            row.title,
            at,
            row.ownerId,
            restorable: await _alive(_db.calendars, row.calendarId),
          ),
      for (final row in await (_db.select(
        _db.wikiPages,
      )..where((r) => r.deletedAt.isNotNull())).get())
        if (row.deletedAt case final at?)
          _entry(
            EntityTypes.wikiPage,
            row.id,
            row.title,
            at,
            row.ownerId,
            restorable: switch (row.parentId) {
              null => true,
              final parent => await _alive(_db.wikiPages, parent),
            },
          ),
      for (final row in await (_db.select(
        _db.tags,
      )..where((r) => r.deletedAt.isNotNull())).get())
        if (row.deletedAt case final at?)
          _entry(EntityTypes.tag, row.id, row.name, at, row.ownerId),
    ]..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return .new(entries: entries, retentionDays: _retentionDays);
  }

  static TrashEntry _entry(
    String type,
    String id,
    String title,
    DateTime deletedAt,
    String ownerId, {
    bool restorable = true,
  }) => .new(
    itemType: type,
    itemId: id,
    title: title,
    deletedAt: deletedAt,
    deletedBy: ownerId,
    remainingDays: (_retentionDays - clock.now().difference(deletedAt).inDays)
        .clamp(0, _retentionDays),
    restorable: restorable,
  );

  /// Whether the container [id] in [table] is there and not deleted.
  Future<bool> _alive(TableInfo<Table, Object?> table, String id) async {
    final row = table as SyncedItem;
    final found =
        await (_db.selectOnly(table)
              ..addColumns([row.id])
              ..where(row.id.equals(id) & row.deletedAt.isNull()))
            .getSingleOrNull();
    return found != null;
  }

  /// Brings an item back — into [targetContainerId] if its own container is gone.
  ///
  /// With every field it holds, not only what the restore changes: while it lay in
  /// the trash, a start without a server dropped everything the outbox held about it
  /// (`LocalTakeover.compact`), as the server never knew it — and what went out after
  /// would have changed an item the server does not have, a page without its title
  /// or kind.
  Future<void> restore(
    String itemType,
    String itemId, {
    String? targetContainerId,
  }) => _writes.run((write) async {
    switch (itemType) {
      case EntityTypes.todoList:
        await _revive(write, _db.todoLists, itemId);
        // Its tasks did not go with it on this device — their rows stayed — but the
        // same start dropped what they had to send, as their list was gone.
        final tasks =
            await (_db.select(_db.todos)..where(
                  (row) => row.listId.equals(itemId) & row.deletedAt.isNull(),
                ))
                .get();
        for (final task in tasks) {
          await _revive(
            write,
            _db.todos,
            task.id,
            containerType: EntityTypes.todoList,
          );
        }
      case EntityTypes.todo:
        final row = await _row(_db.todos, itemId);
        final list = await _target(
          _db.todoLists,
          row.listId,
          targetContainerId,
        );
        if (list != row.listId) {
          await write.change(
            _db.todos,
            TodosCompanion(listId: Value(list)),
            id: itemId,
            version: row.version,
            fields: {WireFields.listId: list},
            containerType: EntityTypes.todoList,
            containerId: list,
            label: row.title,
          );
        }
        await _revive(
          write,
          _db.todos,
          itemId,
          containerType: EntityTypes.todoList,
        );
      case EntityTypes.calendar:
        await _revive(write, _db.calendars, itemId);
      case EntityTypes.event:
        final row = await _row(_db.events, itemId);
        final calendar = await _target(
          _db.calendars,
          row.calendarId,
          targetContainerId,
        );
        if (calendar != row.calendarId) {
          await write.change(
            _db.events,
            EventsCompanion(calendarId: Value(calendar)),
            id: itemId,
            version: row.version,
            fields: {WireFields.calendarId: calendar},
            containerType: EntityTypes.calendar,
            containerId: calendar,
            label: row.title,
          );
        }
        await _revive(
          write,
          _db.events,
          itemId,
          containerType: EntityTypes.calendar,
        );
      case EntityTypes.wikiPage:
        final row = await _row(_db.wikiPages, itemId);
        final parent = switch (row.parentId) {
          null => null,
          final own => await _target(_db.wikiPages, own, targetContainerId),
        };
        if (parent != row.parentId) {
          await write.change(
            _db.wikiPages,
            WikiPagesCompanion(parentId: Value(parent)),
            id: itemId,
            version: row.version,
            fields: {WireFields.parentId: parent},
            containerType: EntityTypes.wikiPage,
            containerId: parent,
            label: row.title,
          );
        }
        await _revive(
          write,
          _db.wikiPages,
          itemId,
          containerType: parent == null ? null : EntityTypes.wikiPage,
        );
        if (row.deletedAt case final since?) {
          await _restoreMap(write, itemId, since);
        }
      case EntityTypes.tag:
        await _revive(write, _db.tags, itemId);
      default:
        throw const HiwiskiFailure(code: FailureCodes.trashItemNotFound);
    }
  });

  /// Brings [id] back with every field it holds, or says it is not in the trash.
  static Future<void> _revive<T extends SyncedItem, D>(
    LocalWrite write,
    TableInfo<T, D> table,
    String id, {
    String? containerType,
  }) async {
    final revived = await write.revive(
      table,
      id: id,
      containerType: containerType,
    );
    if (revived == null) {
      throw const HiwiskiFailure(code: FailureCodes.trashItemNotFound);
    }
  }

  /// A page's pinboard comes back with it, as from a server's trash: its elements
  /// are in no trash of their own, and left behind they were lost for good once the
  /// device moved onto a server. What went with the page — deleted when it was, or
  /// after — and not what was deleted on its own before; a connection only where
  /// both its elements are back.
  Future<void> _restoreMap(
    LocalWrite write,
    String pageId,
    DateTime since,
  ) async {
    final nodes =
        await (_db.select(_db.pinboardNodes)..where(
              (row) =>
                  row.pageId.equals(pageId) &
                  row.deletedAt.isBiggerOrEqualValue(since),
            ))
            .get();
    for (final node in nodes) {
      await write.revive(
        _db.pinboardNodes,
        id: node.id,
        containerType: EntityTypes.wikiPage,
      );
    }
    final edges =
        await (_db.select(_db.pinboardEdges)..where(
              (row) =>
                  row.pageId.equals(pageId) &
                  row.deletedAt.isBiggerOrEqualValue(since),
            ))
            .get();
    for (final edge in edges) {
      if (await _alive(_db.pinboardNodes, edge.fromId) &&
          await _alive(_db.pinboardNodes, edge.toId)) {
        await write.revive(
          _db.pinboardEdges,
          id: edge.id,
          containerType: EntityTypes.wikiPage,
        );
      }
    }
  }

  Future<D> _row<T extends Table, D>(TableInfo<T, D> table, String id) async =>
      await (_db.select(
        table,
      )..where((row) => (row as SyncedItem).id.equals(id))).getSingleOrNull() ??
      (throw const HiwiskiFailure(code: FailureCodes.trashItemNotFound));

  /// The container an item goes back to: its own while it is there, otherwise
  /// [target] — and if there is none, the server's answer: it has to be given.
  Future<String> _target(
    TableInfo<Table, Object?> table,
    String own,
    String? target,
  ) async {
    if (await _alive(table, own)) return own;
    if (target != null && await _alive(table, target)) return target;
    throw const HiwiskiFailure(code: FailureCodes.trashContainerGone);
  }
}
