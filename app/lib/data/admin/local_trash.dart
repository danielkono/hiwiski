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
/// server's, restores an item on its own, not what went with it.
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
  Future<void> restore(
    String itemType,
    String itemId, {
    String? targetContainerId,
  }) => _writes.run((write) async {
    switch (itemType) {
      case EntityTypes.todoList:
        final row = await _row(_db.todoLists, itemId);
        await write.change(
          _db.todoLists,
          const TodoListsCompanion(deletedAt: Value(null)),
          id: itemId,
          version: row.version,
          fields: const {},
          label: row.name,
        );
      case EntityTypes.todo:
        final row = await _row(_db.todos, itemId);
        final list = await _target(
          _db.todoLists,
          row.listId,
          targetContainerId,
        );
        await write.change(
          _db.todos,
          TodosCompanion(deletedAt: const Value(null), listId: Value(list)),
          id: itemId,
          version: row.version,
          fields: {WireFields.listId: list},
          containerType: EntityTypes.todoList,
          containerId: list,
          label: row.title,
        );
      case EntityTypes.calendar:
        final row = await _row(_db.calendars, itemId);
        await write.change(
          _db.calendars,
          const CalendarsCompanion(deletedAt: Value(null)),
          id: itemId,
          version: row.version,
          fields: const {},
          label: row.name,
        );
      case EntityTypes.event:
        final row = await _row(_db.events, itemId);
        final calendar = await _target(
          _db.calendars,
          row.calendarId,
          targetContainerId,
        );
        await write.change(
          _db.events,
          EventsCompanion(
            deletedAt: const Value(null),
            calendarId: Value(calendar),
          ),
          id: itemId,
          version: row.version,
          fields: {WireFields.calendarId: calendar},
          containerType: EntityTypes.calendar,
          containerId: calendar,
          label: row.title,
        );
      case EntityTypes.wikiPage:
        final row = await _row(_db.wikiPages, itemId);
        final parent = switch (row.parentId) {
          null => null,
          final own => await _target(_db.wikiPages, own, targetContainerId),
        };
        await write.change(
          _db.wikiPages,
          WikiPagesCompanion(
            deletedAt: const Value(null),
            parentId: Value(parent),
          ),
          id: itemId,
          version: row.version,
          fields: {WireFields.parentId: parent},
          containerType: parent == null ? null : EntityTypes.wikiPage,
          containerId: parent,
          label: row.title,
        );
      case EntityTypes.tag:
        final row = await _row(_db.tags, itemId);
        await write.change(
          _db.tags,
          const TagsCompanion(deletedAt: Value(null)),
          id: itemId,
          version: row.version,
          fields: const {},
          label: row.name,
        );
      default:
        throw const HiwiskiFailure(code: FailureCodes.trashItemNotFound);
    }
  });

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
