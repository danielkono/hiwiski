import 'package:drift/drift.dart';

// The generated part writes the column defaults as they stand in tables.dart, and they
// name the wire constants.
import '../common/wire.dart';
import 'connection.dart';
import 'tables.dart';

part 'hiwiski_database.drift.dart';

/// The local database — **the single source of truth for the UI**.
///
/// "The client always reads and writes against the local database, never directly
/// against the API. Even where the sync layer does nothing more than pass things
/// through. Otherwise putting in the real layer later becomes a rebuild."
@DriftDatabase(
  tables: [
    TodoLists,
    Todos,
    TodoOccurrences,
    OutboxEntries,
    Conflicts,
    SyncStates,
    Members,
    Calendars,
    Events,
    CalendarSubscriptions,
    CalendarFeeds,
    WikiPages,
    Products,
    Aisles,
    Comments,
    Boards,
    Widgets,
    Tags,
    ListOrders,
    LocalImages,
    LeftBehindItems,
    MindmapNodes,
    MindmapEdges,
  ],
)
class HiwiskiDatabase extends _$HiwiskiDatabase {
  static const _foreignKeysOn = 'PRAGMA foreign_keys = ON';
  static const _tableInfo = 'PRAGMA table_info(';
  static const _tableInfoEnd = ')';
  static const _columnName = 'name';

  /// A file on the device, only memory in the browser — see `connection_web.dart`.
  HiwiskiDatabase([QueryExecutor? executor])
    : super(executor ?? openConnection());

  /// One that lives only while it is open — for the kiosk's tiles, next
  /// to the device's own and never mixed with it.
  HiwiskiDatabase.memory() : super(openMemoryConnection());

  /// The baseline is 19: the tables as the app has them since 2026.1.10, created fresh
  /// on every device. The steps that led there are gone with the devices that needed
  /// them; each change since has its step in [migration].
  ///
  /// 20: a mind map's elements and connections. 21: what a link element shows. 22: the
  /// colour of an element's text. 23: strokes drawn by hand. 24: how thick a connection
  /// is. 25: a connection's kind of line and its arrowheads. 26: how far an element is
  /// turned.
  @override
  int get schemaVersion => 26;

  /// Adds [column] to [table] unless it is there already. A step can be half done:
  /// the column added but the new version not yet written — the background sync
  /// opens the file through a connection of its own and may be stopped by the system
  /// mid-upgrade, or upgrade at the same moment as the app. Every start after that
  /// failed on "duplicate column name", and the app showed nothing.
  Future<void> _addColumnOnce(
    Migrator m,
    TableInfo<Table, Object?> table,
    GeneratedColumn<Object> column,
  ) async {
    final columns = await customSelect(
      '$_tableInfo${table.actualTableName}$_tableInfoEnd',
    ).get();
    if (columns.any((row) => row.read<String>(_columnName) == column.name)) {
      return;
    }
    await m.addColumn(table, column);
  }

  @override
  MigrationStrategy get migration => .new(
    onUpgrade: (m, from, to) async {
      // Locally, too, we migrate instead of recreating. Whoever has had the app on
      // their device for a while may have unsaved work sitting there; a `deleteAndRecreate`
      // would be the cheapest path and the most expensive bug. The steps go here, one
      // `if (from < n)` each.
      //
      // Every upgrade ends in one snapshot. A step that adds a synced column has to
      // fetch what the server already holds for it — pulled by the old app, the
      // unknown field was dropped and never came again. Asked here once, no step can
      // forget it; it is idempotent and costs one snapshot per schema bump.
      if (from < 20) {
        // A mind map's elements and connections: the snapshot below fetches what an
        // older app skipped as a type it did not know.
        await m.createTable(mindmapNodes);
        await m.createTable(mindmapEdges);
      } else {
        // Created above with every column already. A device on 20 keeps its unused
        // `image_id`: pictures stand in the text now, and a column dropped in SQLite
        // means a copy of the table for nothing.
        if (from < 21) {
          await _addColumnOnce(m, mindmapNodes, mindmapNodes.linkView);
        }
        if (from < 22) {
          await _addColumnOnce(m, mindmapNodes, mindmapNodes.textColor);
        }
        if (from < 23) {
          await _addColumnOnce(m, mindmapNodes, mindmapNodes.points);
          await _addColumnOnce(m, mindmapNodes, mindmapNodes.strokeWidth);
        }
        if (from < 24) {
          await _addColumnOnce(m, mindmapEdges, mindmapEdges.strokeWidth);
        }
        if (from < 25) {
          await _addColumnOnce(m, mindmapEdges, mindmapEdges.line);
          await _addColumnOnce(m, mindmapEdges, mindmapEdges.arrows);
        }
        if (from < 26) {
          await _addColumnOnce(m, mindmapNodes, mindmapNodes.rotation);
        }
      }
      await requestSnapshot();
    },
    beforeOpen: (details) async {
      // Without this the foreign keys do not apply, and a deleted list would leave
      // its tasks orphaned.
      await customStatement(_foreignKeysOn);

      // **What is missing gets created.** `createAll` writes
      // `CREATE TABLE IF NOT EXISTS` and is thus a no-op as long as everything is
      // there.
      //
      // That is not a replacement for the migration above but a safety net below it.
      // Once the wiki screen showed
      // `no such table: wiki_pages`: the database in the browser was on schema 2,
      // the step up to 3 had never run — and **the user could not have done
      // anything** except uninstall the app. A local database is a mirror; whatever
      // is missing, the next sync fetches again anyway.
      await Migrator(this).createAll();
    },
  );

  // --- The sync state ----------------------------------------------------------

  static const _lastSeqKey = 'lastSeq';
  static const _instanceIdKey = 'instanceId';

  Future<String?> readState(String key) async {
    final row = await (select(
      syncStates,
    )..where((state) => state.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> writeState(String key, String value) =>
      into(syncStates)
          .insertOnConflictUpdate(SyncStateRow(key: key, value: value));

  Future<int> get lastSeq async =>
      int.tryParse(await readState(_lastSeqKey) ?? '') ?? 0;

  Future<void> setLastSeq(int value) => writeState(_lastSeqKey, '$value');

  Future<String?> get instanceId => readState(_instanceIdKey);

  static const _snapshotFromKey = 'snapshotFrom';

  /// A snapshot is due or was interrupted — and after it the log continues from this
  /// state. `0` means: from the state the server reports at the start of the snapshot.
  /// `null`: none due.
  ///
  /// Persisted and not only in memory, because otherwise an aborted snapshot would
  /// restart on the next launch from a **later** state — and whatever was deleted in
  /// between would remain locally.
  Future<int?> get snapshotFrom async =>
      int.tryParse(await readState(_snapshotFromKey) ?? '');

  Future<void> setSnapshotFrom(int value) =>
      writeState(_snapshotFromKey, '$value');

  /// Request the full snapshot on the next pull without giving up the local state:
  /// afterwards the log continues from the previous state, and nothing that happened
  /// in the meantime falls through.
  Future<void> requestSnapshot() async {
    if (await snapshotFrom != null) return;
    await setSnapshotFrom(await lastSeq);
  }

  /// The snapshot is done: continue with the log from [from].
  Future<void> finishSnapshot(int from) => transaction(() async {
    await setLastSeq(from);
    await (delete(
      syncStates,
    )..where((state) => state.key.equals(_snapshotFromKey))).go();
  });

  Future<void> setInstanceId(String value) => writeState(_instanceIdKey, value);

  static const _ownerKey = 'owner';

  /// Whom the data on this device belongs to: `<member>@<server>`.
  Future<String?> get owner => readState(_ownerKey);

  Future<void> setOwner(String value) => writeState(_ownerKey, value);

  /// **Everything that belongs to a member, gone** — the mirror, the queue, the
  /// conflicts, the sync state.
  ///
  /// Unlike [discardMirroredData], here the outbox does not stay either: it belongs to
  /// whoever is signing out, and under the next person's session it would go out with
  /// their name and their shares. Only the product catalog stays — it belongs to
  /// everyone and has no sharing.
  Future<void> wipeForNextMember() async {
    await transaction(() async {
      await discardMirroredData();
      await delete(outboxEntries).go();
      await delete(conflicts).go();
      // The member's own copy of what a restore left behind: theirs, like the queue.
      await delete(leftBehindItems).go();
      await delete(members).go();
      // Not mirrored: what was added without a server exists only here.
      await delete(localImages).go();
      await delete(syncStates).go();
    });
  }

  /// How much has not reached the server yet — what [wipeForNextMember] would lose:
  /// the changes waiting in the outbox, and the images kept on the device until they
  /// are uploaded after them. An image added to a text counts like the text: signing
  /// out names both.
  Stream<int> watchUnsyncedCount() {
    final changes = subqueryExpression<int>(
      selectOnly(outboxEntries)
        ..addColumns([countAll()])
        ..where(outboxEntries.state.equals(OutboxStates.pending)),
    );
    final images = subqueryExpression<int>(
      selectOnly(localImages)..addColumns([countAll()]),
    );
    final total = changes + images;
    return selectExpressions([total])
        .map((row) => row.read(total) ?? 0)
        .watchSingle();
  }

  /// Throws away everything that comes from the server — and **nothing** that has not
  /// been synced yet.
  ///
  /// For the resync after `resync_required`. The outbox stays: a cleanup that deletes
  /// unsaved work is a trap.
  Future<void> discardMirroredData() async {
    await transaction(() async {
      await delete(todoOccurrences).go();
      await delete(todos).go();
      await delete(todoLists).go();
      await delete(events).go();
      await delete(calendarSubscriptions).go();
      await delete(calendarFeeds).go();
      await delete(calendars).go();
      await delete(mindmapEdges).go();
      await delete(mindmapNodes).go();
      await delete(wikiPages).go();
      await delete(comments).go();
      await delete(widgets).go();
      await delete(boards).go();
      await delete(tags).go();
      await delete(listOrders).go();
      // The catalog belongs to everyone and has no sharing — it comes back on the
      // next fetch anyway, and throwing it away only costs bandwidth.
      await setLastSeq(0);
      await (delete(
        syncStates,
      )..where((state) => state.key.equals(_snapshotFromKey))).go();
    });
  }
}
