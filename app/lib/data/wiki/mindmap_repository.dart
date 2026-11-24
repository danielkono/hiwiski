import 'dart:async';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../../core/common/ids.dart';
import '../../core/common/wire.dart';
import '../../core/db/hiwiski_database.dart';
import '../../core/db/synced_columns.dart';
import '../../core/sync/local_writes.dart';
import '../../domain/wiki/mindmap.dart';

/// A mind map's elements and connections — **always against the local database**.
///
/// Each is an item of its own in its page: every change writes its row and its outbox
/// entry through [LocalWrites], only the fields it touches, so that two people changing
/// different elements — or different fields of one — both get through, offline too.
///
/// Fields go by their names on the wire ([MindmapNode.fields]) and reach their
/// columns through one map ([mindmapNodeColumns]): nothing here names a field of an
/// element's look.
class MindmapRepository {
  MindmapRepository({
    required this._db,
    required this._writes,
    required this._currentMemberId,
  });

  final HiwiskiDatabase _db;
  final LocalWrites _writes;
  final String Function() _currentMemberId;

  late final _nodeColumns = mindmapNodeColumns(_db);
  late final _edgeColumns = mindmapEdgeColumns(_db);

  MindmapNode _nodeOf(MindmapNodeRow row) => .fromFields(
    id: row.id,
    ownerId: row.ownerId,
    version: row.version,
    pageId: row.pageId,
    fields: _nodeColumns.fieldsOf(row),
  );

  MindmapEdge _edgeOf(MindmapEdgeRow row) => .fromFields(
    id: row.id,
    ownerId: row.ownerId,
    version: row.version,
    pageId: row.pageId,
    fields: _edgeColumns.fieldsOf(row),
  );

  // --- Reading -------------------------------------------------------------------

  /// The page's map as it stands on this device — anew whenever an element or a
  /// connection changes. Two of Drift's own query streams, combined: each re-runs on
  /// every change to its table. A stream of table changes read by hand missed a change
  /// that came while the previous read was under way, and the map stayed behind.
  Stream<Mindmap> watchMap(String pageId) {
    final nodes =
        (_db.select(_db.mindmapNodes)..where(
              (row) => row.pageId.equals(pageId) & row.deletedAt.isNull(),
            ))
            .watch();
    final edges =
        (_db.select(_db.mindmapEdges)..where(
              (row) => row.pageId.equals(pageId) & row.deletedAt.isNull(),
            ))
            .watch();
    List<MindmapNodeRow>? lastNodes;
    List<MindmapEdgeRow>? lastEdges;
    StreamSubscription<List<MindmapNodeRow>>? nodeSubscription;
    StreamSubscription<List<MindmapEdgeRow>>? edgeSubscription;
    late final StreamController<Mindmap> combined;
    void emit() {
      final shownNodes = lastNodes;
      final shownEdges = lastEdges;
      if (shownNodes == null || shownEdges == null) return;
      combined.add(
        Mindmap(
          nodes: [for (final row in shownNodes) _nodeOf(row)],
          edges: [for (final row in shownEdges) _edgeOf(row)],
        ),
      );
    }

    combined = StreamController<Mindmap>(
      onListen: () {
        nodeSubscription = nodes.listen((rows) {
          lastNodes = rows;
          emit();
        }, onError: combined.addError);
        edgeSubscription = edges.listen((rows) {
          lastEdges = rows;
          emit();
        }, onError: combined.addError);
      },
      onPause: () {
        nodeSubscription?.pause();
        edgeSubscription?.pause();
      },
      onResume: () {
        nodeSubscription?.resume();
        edgeSubscription?.resume();
      },
      // Not waited for: Drift ends a query stream a moment after its last listener
      // goes, and whoever cancels this one has nothing to wait on — a test's clock
      // that stands still waited for ever.
      onCancel: () {
        unawaited(nodeSubscription?.cancel());
        unawaited(edgeSubscription?.cancel());
      },
    );
    return combined.stream;
  }

  /// An element as it is on this device now — `null` once it is gone. For "Undo",
  /// which may come before the screen has shown the change it takes back.
  Future<MindmapNode?> node(String id) async =>
      switch (await (_db.select(_db.mindmapNodes)
            ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
          .getSingleOrNull()) {
        final row? => _nodeOf(row),
        null => null,
      };

  /// A connection as it is on this device now — `null` once it is gone.
  Future<MindmapEdge?> edge(String id) async =>
      switch (await (_db.select(_db.mindmapEdges)
            ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
          .getSingleOrNull()) {
        final row? => _edgeOf(row),
        null => null,
      };

  /// The living connections at either end of an element.
  Future<List<MindmapEdge>> edgesAt(String nodeId) async => [
    for (final row
        in await (_db.select(_db.mindmapEdges)..where(
              (row) =>
                  (row.fromId.equals(nodeId) | row.toId.equals(nodeId)) &
                  row.deletedAt.isNull(),
            ))
            .get())
      _edgeOf(row),
  ];

  /// Every living element, whatever page it is on — for the link index: a link on a
  /// map is one from its page.
  Stream<List<MindmapNode>> watchAllNodes() =>
      (_db.select(_db.mindmapNodes)..where((row) => row.deletedAt.isNull()))
          .watch()
          .map((rows) => [for (final row in rows) _nodeOf(row)]);

  /// Every living connection with a label, whatever page it is on — for the link
  /// index: a link in a label is one from its page, as on the server.
  Stream<List<MindmapEdge>> watchAllLabelledEdges() =>
      (_db.select(
            _db.mindmapEdges,
          )..where((row) => row.deletedAt.isNull() & row.body.equals('').not()))
          .watch()
          .map((rows) => [for (final row in rows) _edgeOf(row)]);

  /// The page an element or a connection is on — for a conflict, which names only
  /// the item.
  Future<String?> pageOf(String entityType, String id) async =>
      switch (entityType) {
        EntityTypes.mindmapNode => (await (_db.select(
          _db.mindmapNodes,
        )..where((row) => row.id.equals(id))).getSingleOrNull())?.pageId,
        EntityTypes.mindmapEdge => (await (_db.select(
          _db.mindmapEdges,
        )..where((row) => row.id.equals(id))).getSingleOrNull())?.pageId,
        _ => null,
      };

  // --- Elements ------------------------------------------------------------------

  /// Puts a new element on the page's map, above everything there, and returns its
  /// id. [look] holds its other fields by their names on the wire — a link's
  /// target, a colour, a stroke's points ([MindmapNode.fields]).
  Future<String> addNode({
    required String pageId,
    required String kind,
    required int x,
    required int y,
    required int width,
    required int height,
    String text = '',
    Map<String, Object?> look = const {},
    String? id,
  }) async {
    // Given where "Undo" has to know it before it is written.
    final given = id ?? newId();
    await _writes.run((write) async {
      // Read inside the run: nothing gets in between the top and the new element.
      final layer = await _topLayer(pageId);
      final fields = <String, Object?>{
        WireFields.kind: kind,
        WireFields.x: x,
        WireFields.y: y,
        WireFields.width: _size(width),
        WireFields.height: _size(height),
        WireFields.layer: layer,
        WireFields.text: text,
        // What it has: an empty field goes out as none.
        for (final MapEntry(key: field, :value) in look.entries) field: ?value,
      };
      final table = _db.mindmapNodes;
      await write.create(
        table,
        _nodeColumns.rowOf({
          table.id.name: Variable<String>(given),
          table.ownerId.name: Variable<String>(_currentMemberId()),
          table.pageId.name: Variable<String>(pageId),
          ..._nodeColumns.valuesOf(fields),
        }),
        fields: fields,
        containerType: EntityTypes.wikiPage,
        containerId: pageId,
        // On a page created offline: not before the page, and not at all if the page
        // is refused.
        after: pageId,
        label: _labelOf(kind, text),
      );
    });
    return given;
  }

  Future<double> _topLayer(String pageId) async {
    final top = _db.mindmapNodes.layer.max();
    final row =
        await (_db.selectOnly(_db.mindmapNodes)
              ..addColumns([top])
              ..where(
                _db.mindmapNodes.pageId.equals(pageId) &
                    _db.mindmapNodes.deletedAt.isNull(),
              ))
            .getSingleOrNull();
    final highest = row?.read(top);
    return highest == null ? 1 : highest + 1;
  }

  /// Changes an element in [changes] — fields by their names on the wire, `null`
  /// clearing one that may be empty. Only what differs from the element as it is
  /// stored goes out: whoever moves an element while someone else recolours it loses
  /// nothing, and a switch turned on and off again while its sheet is open writes
  /// both times. It goes out on [node]'s version — the one the screen showed — so
  /// that a field someone else changed meanwhile is a conflict, not painted over.
  Future<void> changeNode(MindmapNode node, Map<String, Object?> changes) =>
      changeNodes({node: changes});

  /// Changes several elements in one run — a group moved, aligned or recoloured:
  /// they arrive together or not at all. Each as [changeNode] changes one.
  Future<void> changeNodes(
    Map<MindmapNode, Map<String, Object?>> changes,
  ) async {
    if (changes.isEmpty) return;
    await _writes.run((write) async {
      for (final MapEntry(key: node, value: fields) in changes.entries) {
        await _changeNodeIn(write, node, fields);
      }
    });
  }

  Future<void> _changeNodeIn(
    LocalWrite write,
    MindmapNode node,
    Map<String, Object?> changes,
  ) async {
    final table = _db.mindmapNodes;
    final row = await (_db.select(
      table,
    )..where((row) => row.id.equals(node.id))).getSingleOrNull();
    final stored = row == null ? node.fields : _nodeColumns.fieldsOf(row);
    final fields = <String, Object?>{
      for (final MapEntry(key: field, :value) in changes.entries)
        if (_fitted(field, value) case final wanted
            when wanted != stored[field])
          field: wanted,
    };
    if (fields.isEmpty) return;
    await write.change(
      table,
      _nodeColumns.rowOf({
        table.id.name: Variable<String>(node.id),
        ..._nodeColumns.valuesOf(fields),
      }),
      id: node.id,
      version: node.version,
      fields: fields,
      containerType: EntityTypes.wikiPage,
      containerId: node.pageId,
      label: _labelOf(node.kind, switch (fields[WireFields.text]) {
        final String text => text,
        _ => node.text,
      }),
    );
  }

  /// [value] as [field] keeps it: every size an element gets passes here ([_size]).
  static Object? _fitted(String field, Object? value) =>
      switch ((field, value)) {
        (WireFields.width || WireFields.height, final int size) => _size(size),
        _ => value,
      };

  /// Takes an element away, and its connections with it — locally at once; the server
  /// does the same when the delete arrives.
  Future<void> deleteNode(MindmapNode node) async {
    final now = clock.now();
    await _writes.run((write) async {
      final deleted = await write.delete(
        _db.mindmapNodes,
        id: node.id,
        version: node.version,
        label: _labelOf(node.kind, node.text),
        at: now,
      );
      await write.cascade(
        deleted,
        _db.mindmapEdges,
        MindmapEdgesCompanion(deletedAt: Value(now)),
        where: (row) =>
            (row.fromId.equals(node.id) | row.toId.equals(node.id)) &
            row.deletedAt.isNull(),
      );
    });
  }

  /// Brings elements and connections back as [nodes] and [edges] show them — what
  /// "Undo" does after a delete, and "Redo" after taking a placement back. Each goes
  /// out with all its fields: an upsert brings a deleted item back on the server, and
  /// a device that saw it go has nothing left to merge it into.
  Future<void> restore({
    List<MindmapNode> nodes = const [],
    List<MindmapEdge> edges = const [],
  }) => _writes.run((write) async {
    final nodeTable = _db.mindmapNodes;
    for (final node in nodes) {
      final row = await (_db.select(
        nodeTable,
      )..where((row) => row.id.equals(node.id))).getSingleOrNull();
      final fields = node.fields;
      final values = _nodeColumns.rowOf({
        nodeTable.id.name: Variable<String>(node.id),
        nodeTable.ownerId.name: Variable<String>(
          row?.ownerId ?? _currentMemberId(),
        ),
        nodeTable.pageId.name: Variable<String>(node.pageId),
        ..._nodeColumns.valuesOf(fields),
        nodeTable.deletedAt.name: const Variable<DateTime>(null),
      });
      if (row == null) {
        await write.create(
          nodeTable,
          values,
          fields: fields,
          containerType: EntityTypes.wikiPage,
          containerId: node.pageId,
          after: node.pageId,
          label: _labelOf(node.kind, node.text),
        );
      } else {
        await write.change(
          nodeTable,
          values,
          id: node.id,
          version: row.version,
          fields: fields,
          containerType: EntityTypes.wikiPage,
          containerId: node.pageId,
          label: _labelOf(node.kind, node.text),
        );
      }
    }
    final edgeTable = _db.mindmapEdges;
    for (final edge in edges) {
      final row = await (_db.select(
        edgeTable,
      )..where((row) => row.id.equals(edge.id))).getSingleOrNull();
      final fields = edge.fields;
      final values = _edgeColumns.rowOf({
        edgeTable.id.name: Variable<String>(edge.id),
        edgeTable.ownerId.name: Variable<String>(
          row?.ownerId ?? _currentMemberId(),
        ),
        edgeTable.pageId.name: Variable<String>(edge.pageId),
        ..._edgeColumns.valuesOf(fields),
        edgeTable.deletedAt.name: const Variable<DateTime>(null),
      });
      if (row == null) {
        await write.create(
          edgeTable,
          values,
          fields: fields,
          containerType: EntityTypes.wikiPage,
          containerId: edge.pageId,
          after: edge.fromId.compareTo(edge.toId) > 0 ? edge.fromId : edge.toId,
          alsoAfter: [edge.fromId, edge.toId],
          label: _edgeLabelOf(edge.text),
        );
      } else {
        await write.change(
          edgeTable,
          values,
          id: edge.id,
          version: row.version,
          fields: fields,
          containerType: EntityTypes.wikiPage,
          containerId: edge.pageId,
          // Brought back, it needs both its elements back on the server too.
          alsoAfter: [edge.fromId, edge.toId],
          label: _edgeLabelOf(edge.text),
        );
      }
    }
  });

  // --- Connections ---------------------------------------------------------------

  /// Connects [from] and [to] and returns the connection's id. [look] holds its
  /// other fields by their names on the wire — a colour, a line, arrow heads
  /// ([MindmapEdge.fields]).
  Future<String> connect(
    MindmapNode from,
    MindmapNode to, {
    String text = '',
    Map<String, Object?> look = const {},
    String? id,
  }) async {
    final given = id ?? newId();
    final fields = <String, Object?>{
      WireFields.fromId: from.id,
      WireFields.toId: to.id,
      WireFields.text: text,
      // What it has: an empty field goes out as none.
      for (final MapEntry(key: field, :value) in look.entries) field: ?value,
    };
    final table = _db.mindmapEdges;
    await _writes.run(
      (write) => write.create(
        table,
        _edgeColumns.rowOf({
          table.id.name: Variable<String>(given),
          table.ownerId.name: Variable<String>(_currentMemberId()),
          table.pageId.name: Variable<String>(from.pageId),
          ..._edgeColumns.valuesOf(fields),
        }),
        fields: fields,
        containerType: EntityTypes.wikiPage,
        containerId: from.pageId,
        // Not before either end: elements go out in the order they were made, so
        // hung off the newer it follows both — and an element held back or refused
        // holds the connection back too, instead of letting it fail on its own.
        after: from.id.compareTo(to.id) > 0 ? from.id : to.id,
        alsoAfter: [from.id, to.id],
        label: _edgeLabelOf(text),
      ),
    );
    return given;
  }

  /// Changes a connection in [changes] — its label, colour, thickness, line or arrow
  /// heads, by their names on the wire — as [changeNode] changes an element.
  Future<void> changeEdge(MindmapEdge edge, Map<String, Object?> changes) =>
      _writes.run((write) async {
        final table = _db.mindmapEdges;
        final row = await (_db.select(
          table,
        )..where((row) => row.id.equals(edge.id))).getSingleOrNull();
        final stored = row == null ? edge.fields : _edgeColumns.fieldsOf(row);
        final fields = <String, Object?>{
          for (final MapEntry(key: field, :value) in changes.entries)
            if (value != stored[field]) field: value,
        };
        if (fields.isEmpty) return;
        await write.change(
          table,
          _edgeColumns.rowOf({
            table.id.name: Variable<String>(edge.id),
            ..._edgeColumns.valuesOf(fields),
          }),
          id: edge.id,
          version: edge.version,
          fields: fields,
          containerType: EntityTypes.wikiPage,
          containerId: edge.pageId,
          label: _edgeLabelOf(switch (fields[WireFields.text]) {
            final String text => text,
            _ => edge.text,
          }),
        );
      });

  Future<void> deleteEdge(MindmapEdge edge) => _writes.run(
    (write) => write.delete(
      _db.mindmapEdges,
      id: edge.id,
      version: edge.version,
      label: _edgeLabelOf(edge.text),
    ),
  );

  /// A width or height as the server keeps it: from 1 to [mindmapMaxSize]. Every
  /// size an element gets passes here — resized, aligned, sized for its text, a
  /// stroke drawn across the map zoomed out — and one beyond it was refused for good.
  static int _size(int value) => value.clamp(1, mindmapMaxSize);

  /// Takes several elements away at once — the strokes a swipe of the eraser went
  /// over: one run, they go together.
  Future<void> deleteNodes(List<MindmapNode> nodes) async {
    final now = clock.now();
    await _writes.run((write) async {
      for (final node in nodes) {
        final deleted = await write.delete(
          _db.mindmapNodes,
          id: node.id,
          version: node.version,
          label: _labelOf(node.kind, node.text),
          at: now,
        );
        await write.cascade(
          deleted,
          _db.mindmapEdges,
          MindmapEdgesCompanion(deletedAt: Value(now)),
          where: (row) =>
              (row.fromId.equals(node.id) | row.toId.equals(node.id)) &
              row.deletedAt.isNull(),
        );
      }
    });
  }

  /// What a change is called in the list of what could not sync — empty where the
  /// item has no words of its own: the list names it by its kind of item then. Its
  /// kind's code, or a picture's Markdown, read as nothing anyone wrote.
  static String _labelOf(String kind, String text) =>
      mindmapLabelOf(kind, text);

  /// What a change of a connection is called there ([_labelOf]).
  static String _edgeLabelOf(String text) =>
      mindmapLabelOf(MindmapKinds.plain, text);
}
