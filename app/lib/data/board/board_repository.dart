import 'dart:async';

import 'package:drift/drift.dart';

import '../../core/common/wire.dart';
import '../../core/db/hiwiski_database.dart';
import '../../core/common/ids.dart';
import '../../core/sync/local_writes.dart';
import '../../domain/board/board_items.dart';
import '../../domain/board/widget_kinds.dart';

/// Boards and tiles — **always against the local database**.
class BoardRepository {
  BoardRepository({
    required this._db,
    required this._writes,
    required this._currentMemberId,
  });

  final HiwiskiDatabase _db;
  final LocalWrites _writes;
  final String Function() _currentMemberId;

  String get _ownerId => _currentMemberId();

  Stream<List<Board>> watchBoards() =>
      (_db.select(_db.boards)..where((row) => row.deletedAt.isNull()))
          .watch()
          .map((rows) => [for (final row in rows) row.toDomain()]);

  /// Whether this device has never pulled anything yet — then "no board" is no
  /// answer, the board may well be on its way.
  Future<bool> neverPulled() async => await _db.lastSeq == 0;

  /// The board of [kind] among [boards] — created if there is none; `null` while it
  /// is too early to tell.
  ///
  /// Nothing is created before the stock has been read: otherwise one would come
  /// into being although one may already be on its way — and the server would
  /// reject the second.
  ///
  /// **And not before the first sync either.** A new device — the phone that opens
  /// the page for the first time — has an empty database. The stream delivers `[]`,
  /// the app created a start board, and the server rejected it
  /// (`sync.constraint_violated`) because the computer had one long ago. So: only
  /// once the sync has [answered] does "no board" count as an answer. Offline it is
  /// still created — the app does not block anything.
  Future<Board?> boardOf(
    String kind,
    List<Board> boards, {
    required bool answered,
  }) async {
    final existing = boards.where((board) => board.kind == kind).firstOrNull;
    if (existing != null) return existing;
    if (!answered && await neverPulled()) return null;
    return ensure(kind);
  }

  Stream<List<BoardWidget>> watchWidgets(String boardId) =>
      (_db.select(_db.widgets)
            ..where(
              (row) => row.boardId.equals(boardId) & row.deletedAt.isNull(),
            )
            ..orderBy([
              (row) => OrderingTerm.asc(row.gridY),
              (row) => OrderingTerm.asc(row.gridX),
              (row) => OrderingTerm.asc(row.position),
            ]))
          .watch()
          .map((rows) => [for (final row in rows) row.toDomain()]);

  /// Fetches the board of this kind — and **creates it if there is none**.
  ///
  /// "Both come into being on their own the first time they are opened — an empty screen
  /// with a 'Create board' button would be a question with only one answer."
  /// Creations in flight, per kind.
  ///
  /// **Without this the app creates two boards.** The provider above it reruns as soon as
  /// the stock stream emits for the first time — and at that moment the first call has
  /// not finished yet. Both see no board and create one; the server rejects the
  /// second (`board_one_per_kind`), and the user sees "Change could not be
  /// applied" on the next task they create.
  ///
  /// A memo instead of a lock: whoever asks second gets the same result as the
  /// first — and that is exactly the answer they wanted.
  final Map<String, Future<Board>> _pending = {};

  Future<Board> ensure(String kind) =>
      _pending.putIfAbsent(kind, () => _ensure(kind)).whenComplete(() {
        _pending.remove(kind);
      });

  Future<Board> _ensure(String kind) {
    final dashboard = kind == BoardKinds.dashboard;

    // **Check and create in one transaction.** Drift runs transactions one after
    // another; so nothing can get in between the check and the insert — not
    // even from another screen.
    return _writes.run((write) async {
      final existing =
          await (_db.select(
                _db.boards,
              )..where((row) => row.kind.equals(kind) & row.deletedAt.isNull()))
              .getSingleOrNull();
      if (existing != null) return existing.toDomain();

      final id = newId();
      final row = BoardRow(
        id: id,
        ownerId: _ownerId,
        version: 0,
        kind: kind,
        name: '',
        layout: dashboard ? BoardLayouts.grid : BoardLayouts.flow,
        columns: dashboard ? 4 : 1,
        token: dashboard ? newToken() : null,
      );

      await write.create(
        _db.boards,
        row,
        fields: {
          WireFields.kind: kind,
          WireFields.layout: row.layout,
          WireFields.columns: row.columns,
          WireFields.token: ?row.token,
        },
        label: kind,
      );
      return row.toDomain();
    });
  }

  /// A new address. **The old one is dead immediately**.
  static String newToken() => newId().replaceAll('-', '');

  Future<void> regenerateToken(Board board) =>
      _updateBoard(board, {WireFields.token: newToken()});

  /// Changes a board — each field only if given.
  Future<void> updateBoard(
    Board board, {
    String? name,
    String? layout,
    int? columns,
  }) {
    final fields = <String, dynamic>{
      WireFields.name: ?name,
      WireFields.layout: ?layout,
      WireFields.columns: ?columns,
    };
    return fields.isEmpty ? Future.value() : _updateBoard(board, fields);
  }

  Future<void> _updateBoard(Board board, Map<String, dynamic> fields) async {
    await _writes.run((write) async {
      if (fields[WireFields.columns] case final int columns
          when columns < board.columns) {
        await _reflow(write, board.id, columns);
      }
      await write.change(
        _db.boards,
        BoardsCompanion(
          name: fields.containsKey(WireFields.name)
              ? Value(fields[WireFields.name] as String? ?? '')
              : const Value.absent(),
          layout: fields.containsKey(WireFields.layout)
              ? Value(fields[WireFields.layout] as String? ?? BoardLayouts.flow)
              : const Value.absent(),
          columns: fields.containsKey(WireFields.columns)
              ? Value((fields[WireFields.columns] as num?)?.toInt() ?? 4)
              : const Value.absent(),
          token: fields.containsKey(WireFields.token)
              ? Value(fields[WireFields.token] as String?)
              : const Value.absent(),
        ),
        id: board.id,
        version: board.version,
        fields: fields,
        label: board.kind,
      );
    });
  }

  /// Fewer columns: the tiles that no longer fit move to the first free spots, at
  /// most as wide as the grid. Left where they were, they sat outside it — cut off on
  /// the dashboard and the kiosk, and out of reach to be moved back.
  Future<void> _reflow(LocalWrite write, String boardId, int columns) async {
    final rows =
        await (_db.select(_db.widgets)
              ..where(
                (row) => row.boardId.equals(boardId) & row.deletedAt.isNull(),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.gridY),
                (row) => OrderingTerm.asc(row.gridX),
              ]))
            .get();
    final tiles = [for (final row in rows) row.toDomain()];
    final placed = [
      for (final tile in tiles)
        if (fitsColumns(tile, columns)) tile,
    ];
    for (final tile in tiles) {
      if (fitsColumns(tile, columns)) continue;
      final (:x, :y, :width) = firstFreeCell(
        placed,
        columns,
        tile.gridW,
        tile.gridH,
      );
      await _writeWidget(write, tile, {
        WireFields.gridX: x,
        WireFields.gridY: y,
        WireFields.gridW: width,
      });
      placed.add(tile.placedAt(x: x, y: y, width: width, height: tile.gridH));
    }
  }

  Future<String> addWidget({
    required Board board,
    required String kind,
    required List<BoardWidget> existing,
    WidgetConfig? config,
  }) async {
    final id = newId();
    final (:x, :y, :width) = board.layout == BoardLayouts.grid
        ? firstFreeCell(existing, board.columns, 2, 2)
        : (x: 0, y: 0, width: 2);
    final encoded = (config ?? WidgetConfig({})).encode();

    await _writes.run(
      (write) => write.create(
        _db.widgets,
        WidgetsCompanion.insert(
          id: id,
          ownerId: _ownerId,
          boardId: board.id,
          kind: kind,
          config: Value(encoded),
          gridX: Value(x),
          gridY: Value(y),
          gridW: Value(width),
          gridH: const Value(2),
          position: Value(existing.length),
        ),
        fields: {
          WireFields.kind: kind,
          WireFields.config: (config ?? WidgetConfig({})).values,
          WireFields.gridX: x,
          WireFields.gridY: y,
          WireFields.gridW: width,
          WireFields.gridH: 2,
          WireFields.position: existing.length,
        },
        containerType: EntityTypes.board,
        containerId: board.id,
        after: board.id,
        label: kind,
      ),
    );
    return id;
  }

  /// Sets a tile's configuration.
  Future<void> configureWidget(BoardWidget widget, WidgetConfig config) =>
      _updateWidget(widget, {WireFields.config: config.values});

  Future<void> _updateWidget(
    BoardWidget widget,
    Map<String, dynamic> fields,
  ) async {
    await _writes.run((write) => _writeWidget(write, widget, fields));
  }

  /// A tile's fields, locally and into the outbox.
  Future<void> _writeWidget(
    LocalWrite write,
    BoardWidget widget,
    Map<String, dynamic> fields,
  ) async {
    await write.change(
      _db.widgets,
      WidgetsCompanion(
        config: switch (fields[WireFields.config]) {
          final Map<dynamic, dynamic> config => Value(
            WidgetConfig(config.cast<String, dynamic>()).encode(),
          ),
          _ => const Value.absent(),
        },
        gridX: _int(fields, WireFields.gridX),
        gridY: _int(fields, WireFields.gridY),
        gridW: _int(fields, WireFields.gridW),
        gridH: _int(fields, WireFields.gridH),
        position: _int(fields, WireFields.position),
      ),
      id: widget.id,
      version: widget.version,
      fields: fields,
      containerType: EntityTypes.board,
      containerId: widget.boardId,
      label: widget.kind,
    );
  }

  /// Swaps two tiles: each goes to the other's place, at its own size — unless that
  /// makes them overlap each other or a third.
  ///
  /// Dragging a tile onto another used to move it onto the other's spot, which the
  /// other still held: every drop was refused as "occupied", and nothing could be
  /// rearranged by dragging at all.
  ///
  /// @return `false` if they do not fit swapped — the caller then says so.
  Future<bool> swapWidgets(
    BoardWidget dragged,
    BoardWidget target,
    List<BoardWidget> all, {
    required int columns,
  }) async {
    final draggedThere = dragged.placedAt(
      x: target.gridX,
      y: target.gridY,
      width: dragged.gridW,
      height: dragged.gridH,
    );
    final targetHere = target.placedAt(
      x: dragged.gridX,
      y: dragged.gridY,
      width: target.gridW,
      height: target.gridH,
    );
    final rest = all.where(
      (other) => other.id != dragged.id && other.id != target.id,
    );
    final blocked =
        !fitsColumns(draggedThere, columns) ||
        !fitsColumns(targetHere, columns) ||
        widgetsOverlap(draggedThere, targetHere) ||
        rest.any(
          (other) =>
              widgetsOverlap(draggedThere, other) ||
              widgetsOverlap(targetHere, other),
        );
    if (blocked) return false;

    await _writes.run((write) async {
      await _writeWidget(write, dragged, {
        WireFields.gridX: target.gridX,
        WireFields.gridY: target.gridY,
      });
      await _writeWidget(write, target, {
        WireFields.gridX: dragged.gridX,
        WireFields.gridY: dragged.gridY,
      });
    });
    return true;
  }

  /// Moves a tile — **unless the spot is taken**.
  ///
  /// "Gaps are allowed, overlaps are rejected by the board: a tile underneath another
  /// would be invisible, and nobody would know where it went."
  ///
  /// @return `false` if the spot is taken — the caller then says so.
  Future<bool> moveWidget(
    BoardWidget widget,
    List<BoardWidget> others,
    int x,
    int y, {
    int? width,
    int? height,
    required int columns,
  }) async {
    final moved = widget.placedAt(
      x: x,
      y: y,
      width: width ?? widget.gridW,
      height: height ?? widget.gridH,
    );
    // Inside the grid, too: a tile past its right edge was cut off and could not be
    // reached to move it back.
    final blocked =
        !fitsColumns(moved, columns) ||
        others
            .where((other) => other.id != widget.id)
            .any((other) => widgetsOverlap(moved, other));
    if (blocked) return false;

    await _updateWidget(widget, {
      WireFields.gridX: x,
      WireFields.gridY: y,
      WireFields.gridW: moved.gridW,
      WireFields.gridH: moved.gridH,
    });
    return true;
  }

  Future<void> deleteWidget(BoardWidget widget) async {
    await _writes.run(
      (write) => write.delete(
        _db.widgets,
        id: widget.id,
        version: widget.version,
        label: widget.kind,
      ),
    );
  }

  static Value<int> _int(Map<String, dynamic> fields, String name) =>
      fields.containsKey(name)
      ? .new((fields[name] as num?)?.toInt() ?? 0)
      : const .absent();
}

extension on BoardRow {
  Board toDomain() => .new(
    id: id,
    ownerId: ownerId,
    version: version,
    deletedAt: deletedAt,
    kind: kind,
    name: name,
    layout: layout,
    columns: columns,
    token: token,
  );
}

extension on WidgetRow {
  BoardWidget toDomain() => .new(
    id: id,
    ownerId: ownerId,
    version: version,
    deletedAt: deletedAt,
    boardId: boardId,
    kind: kind,
    config: config,
    gridX: gridX,
    gridY: gridY,
    gridW: gridW,
    gridH: gridH,
    position: position,
  );
}
