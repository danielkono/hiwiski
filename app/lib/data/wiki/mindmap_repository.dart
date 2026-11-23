import 'dart:async';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../../core/common/ids.dart';
import '../../core/common/wire.dart';
import '../../core/db/hiwiski_database.dart';
import '../../core/sync/local_writes.dart';
import '../../domain/common/change.dart';
import '../../domain/wiki/mindmap.dart';

/// A mind map's elements and connections — **always against the local database**.
///
/// Each is an item of its own in its page: every change writes its row and its outbox
/// entry through [LocalWrites], only the fields it touches, so that two people changing
/// different elements — or different fields of one — both get through, offline too.
class MindmapRepository {
  MindmapRepository({
    required this._db,
    required this._writes,
    required this._currentMemberId,
  });

  final HiwiskiDatabase _db;
  final LocalWrites _writes;
  final String Function() _currentMemberId;

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
          nodes: [for (final row in shownNodes) row.toDomain()],
          edges: [for (final row in shownEdges) row.toDomain()],
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
      (await (_db.select(_db.mindmapNodes)
                ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
              .getSingleOrNull())
          ?.toDomain();

  /// A connection as it is on this device now — `null` once it is gone.
  Future<MindmapEdge?> edge(String id) async =>
      (await (_db.select(_db.mindmapEdges)
                ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
              .getSingleOrNull())
          ?.toDomain();

  /// The living connections at either end of an element.
  Future<List<MindmapEdge>> edgesAt(String nodeId) async => [
    for (final row
        in await (_db.select(_db.mindmapEdges)..where(
              (row) =>
                  (row.fromId.equals(nodeId) | row.toId.equals(nodeId)) &
                  row.deletedAt.isNull(),
            ))
            .get())
      row.toDomain(),
  ];

  /// Every living element, whatever page it is on — for the link index: a link on a
  /// map is one from its page.
  Stream<List<MindmapNode>> watchAllNodes() =>
      (_db.select(_db.mindmapNodes)..where((row) => row.deletedAt.isNull()))
          .watch()
          .map((rows) => [for (final row in rows) row.toDomain()]);

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

  /// Puts a new element on the page's map, above everything there, and returns its id.
  Future<String> addNode({
    required String pageId,
    required String kind,
    required int x,
    required int y,
    required int width,
    required int height,
    String text = '',
    String? target,
    String? linkView,
    String? color,
    String? shape,
    String? points,
    int? strokeWidth,
    String? id,
  }) async {
    // Given where "Undo" has to know it before it is written.
    final given = id ?? newId();
    await _writes.run((write) async {
      // Read inside the run: nothing gets in between the top and the new element.
      final layer = await _topLayer(pageId);
      await write.create(
        _db.mindmapNodes,
        MindmapNodesCompanion.insert(
          id: given,
          ownerId: _currentMemberId(),
          pageId: pageId,
          kind: Value(kind),
          x: Value(x),
          y: Value(y),
          width: Value(_size(width)),
          height: Value(_size(height)),
          layer: Value(layer),
          body: Value(text),
          target: Value(target),
          linkView: Value(linkView),
          color: Value(color),
          shape: Value(shape),
          points: Value(points),
          strokeWidth: Value(strokeWidth),
        ),
        fields: {
          WireFields.kind: kind,
          WireFields.x: x,
          WireFields.y: y,
          WireFields.width: _size(width),
          WireFields.height: _size(height),
          WireFields.layer: layer,
          WireFields.text: text,
          WireFields.target: ?target,
          WireFields.linkView: ?linkView,
          WireFields.color: ?color,
          WireFields.shape: ?shape,
          WireFields.points: ?points,
          WireFields.strokeWidth: ?strokeWidth,
        },
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

  /// Changes an element — each field only if given; [color], [shape], [textSize]
  /// and [textColor] are cleared with `Change(null)`. Only what changes goes out: whoever
  /// moves an element while someone else recolours it loses nothing.
  Future<void> changeNode(
    MindmapNode node, {
    int? x,
    int? y,
    int? width,
    int? height,
    double? layer,
    String? text,
    String? target,
    Change<String?>? linkView,
    Change<String?>? color,
    Change<String?>? shape,
    Change<String?>? textSize,
    Change<String?>? textColor,
    Change<int?>? strokeWidth,
    Change<int?>? rotation,
  }) async {
    final row = MindmapNodesCompanion(
      id: Value(node.id),
      x: _changed(x, node.x),
      y: _changed(y, node.y),
      width: _changed(width == null ? null : _size(width), node.width),
      height: _changed(height == null ? null : _size(height), node.height),
      layer: _changed(layer, node.layer),
      body: _changed(text, node.text),
      target: _changed(target, node.target),
      linkView: _cleared(linkView, node.linkView),
      color: _cleared(color, node.color),
      shape: _cleared(shape, node.shape),
      textSize: _cleared(textSize, node.textSize),
      textColor: _cleared(textColor, node.textColor),
      strokeWidth: strokeWidth == null || strokeWidth.value == node.strokeWidth
          ? const .absent()
          : .new(strokeWidth.value),
      rotation: rotation == null || rotation.value == node.rotation
          ? const .absent()
          : .new(rotation.value),
    );
    final fields = <String, dynamic>{
      if (row.x case Value(present: true, :final value)) WireFields.x: value,
      if (row.y case Value(present: true, :final value)) WireFields.y: value,
      if (row.width case Value(present: true, :final value))
        WireFields.width: value,
      if (row.height case Value(present: true, :final value))
        WireFields.height: value,
      if (row.layer case Value(present: true, :final value))
        WireFields.layer: value,
      if (row.body case Value(present: true, :final value))
        WireFields.text: value,
      if (row.target case Value(present: true, :final value))
        WireFields.target: value,
      if (row.linkView case Value(present: true, :final value))
        WireFields.linkView: value,
      if (row.color case Value(present: true, :final value))
        WireFields.color: value,
      if (row.shape case Value(present: true, :final value))
        WireFields.shape: value,
      if (row.textSize case Value(present: true, :final value))
        WireFields.textSize: value,
      if (row.textColor case Value(present: true, :final value))
        WireFields.textColor: value,
      if (row.strokeWidth case Value(present: true, :final value))
        WireFields.strokeWidth: value,
      if (row.rotation case Value(present: true, :final value))
        WireFields.rotation: value,
    };
    if (fields.isEmpty) return;
    await _writes.run(
      (write) => write.change(
        _db.mindmapNodes,
        row,
        id: node.id,
        version: node.version,
        fields: fields,
        containerType: EntityTypes.wikiPage,
        containerId: node.pageId,
        label: _labelOf(node.kind, text ?? node.text),
      ),
    );
  }

  /// Moves several elements at once — a selection dragged together. One run: they
  /// arrive together or not at all.
  Future<void> moveNodes(Map<MindmapNode, ({int x, int y})> moves) async {
    await _writes.run((write) async {
      for (final MapEntry(key: node, value: to) in moves.entries) {
        final fields = <String, dynamic>{
          if (to.x != node.x) WireFields.x: to.x,
          if (to.y != node.y) WireFields.y: to.y,
        };
        if (fields.isEmpty) continue;
        await write.change(
          _db.mindmapNodes,
          MindmapNodesCompanion(
            id: Value(node.id),
            x: _changed(to.x, node.x),
            y: _changed(to.y, node.y),
          ),
          id: node.id,
          version: node.version,
          fields: fields,
          containerType: EntityTypes.wikiPage,
          containerId: node.pageId,
          label: _labelOf(node.kind, node.text),
        );
      }
    });
  }

  /// Moves and resizes several elements in one go: [places] holds each one's new
  /// box. Only what differs goes out.
  Future<void> arrangeNodes(
    Map<MindmapNode, ({int x, int y, int width, int height})> places,
  ) async {
    await _writes.run((write) async {
      for (final MapEntry(key: node, value: to) in places.entries) {
        final width = _size(to.width);
        final height = _size(to.height);
        final fields = <String, dynamic>{
          if (to.x != node.x) WireFields.x: to.x,
          if (to.y != node.y) WireFields.y: to.y,
          if (width != node.width) WireFields.width: width,
          if (height != node.height) WireFields.height: height,
        };
        if (fields.isEmpty) continue;
        await write.change(
          _db.mindmapNodes,
          MindmapNodesCompanion(
            id: Value(node.id),
            x: _changed(to.x, node.x),
            y: _changed(to.y, node.y),
            width: _changed(width, node.width),
            height: _changed(height, node.height),
          ),
          id: node.id,
          version: node.version,
          fields: fields,
          containerType: EntityTypes.wikiPage,
          containerId: node.pageId,
          label: _labelOf(node.kind, node.text),
        );
      }
    });
  }

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
    for (final node in nodes) {
      final row = await (_db.select(
        _db.mindmapNodes,
      )..where((row) => row.id.equals(node.id))).getSingleOrNull();
      final fields = <String, dynamic>{
        WireFields.kind: node.kind,
        WireFields.x: node.x,
        WireFields.y: node.y,
        WireFields.width: node.width,
        WireFields.height: node.height,
        WireFields.layer: node.layer,
        WireFields.text: node.text,
        WireFields.target: node.target,
        WireFields.linkView: node.linkView,
        WireFields.color: node.color,
        WireFields.shape: node.shape,
        WireFields.textSize: node.textSize,
        WireFields.textColor: node.textColor,
        WireFields.points: node.points,
        WireFields.strokeWidth: node.strokeWidth,
        WireFields.rotation: node.rotation,
      };
      final values = MindmapNodesCompanion(
        id: Value(node.id),
        ownerId: Value(row?.ownerId ?? _currentMemberId()),
        pageId: Value(node.pageId),
        kind: Value(node.kind),
        x: Value(node.x),
        y: Value(node.y),
        width: Value(node.width),
        height: Value(node.height),
        layer: Value(node.layer),
        body: Value(node.text),
        target: Value(node.target),
        linkView: Value(node.linkView),
        color: Value(node.color),
        shape: Value(node.shape),
        textSize: Value(node.textSize),
        textColor: Value(node.textColor),
        points: Value(node.points),
        strokeWidth: Value(node.strokeWidth),
        rotation: Value(node.rotation),
        deletedAt: const Value(null),
      );
      if (row == null) {
        await write.create(
          _db.mindmapNodes,
          values,
          fields: fields,
          containerType: EntityTypes.wikiPage,
          containerId: node.pageId,
          after: node.pageId,
          label: _labelOf(node.kind, node.text),
        );
      } else {
        await write.change(
          _db.mindmapNodes,
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
    for (final edge in edges) {
      final row = await (_db.select(
        _db.mindmapEdges,
      )..where((row) => row.id.equals(edge.id))).getSingleOrNull();
      final fields = <String, dynamic>{
        WireFields.fromId: edge.fromId,
        WireFields.toId: edge.toId,
        WireFields.text: edge.text,
        WireFields.color: edge.color,
        WireFields.strokeWidth: edge.strokeWidth,
        WireFields.line: edge.line,
        WireFields.arrows: edge.arrows,
      };
      final values = MindmapEdgesCompanion(
        id: Value(edge.id),
        ownerId: Value(row?.ownerId ?? _currentMemberId()),
        pageId: Value(edge.pageId),
        fromId: Value(edge.fromId),
        toId: Value(edge.toId),
        body: Value(edge.text),
        color: Value(edge.color),
        strokeWidth: Value(edge.strokeWidth),
        line: Value(edge.line),
        arrows: Value(edge.arrows),
        deletedAt: const Value(null),
      );
      if (row == null) {
        await write.create(
          _db.mindmapEdges,
          values,
          fields: fields,
          containerType: EntityTypes.wikiPage,
          containerId: edge.pageId,
          after: edge.fromId.compareTo(edge.toId) > 0 ? edge.fromId : edge.toId,
          alsoAfter: [edge.fromId, edge.toId],
          label: edge.text,
        );
      } else {
        await write.change(
          _db.mindmapEdges,
          values,
          id: edge.id,
          version: row.version,
          fields: fields,
          containerType: EntityTypes.wikiPage,
          containerId: edge.pageId,
          // Brought back, it needs both its elements back on the server too.
          alsoAfter: [edge.fromId, edge.toId],
          label: edge.text,
        );
      }
    }
  });

  // --- Connections ---------------------------------------------------------------

  /// Connects [from] and [to] and returns the connection's id.
  Future<String> connect(
    MindmapNode from,
    MindmapNode to, {
    String text = '',
    String? color,
    String? line,
    String? arrows,
    int? strokeWidth,
    String? id,
  }) async {
    final given = id ?? newId();
    await _writes.run(
      (write) => write.create(
        _db.mindmapEdges,
        MindmapEdgesCompanion.insert(
          id: given,
          ownerId: _currentMemberId(),
          pageId: from.pageId,
          fromId: from.id,
          toId: to.id,
          body: Value(text),
          color: Value(color),
          strokeWidth: Value(strokeWidth),
          line: Value(line),
          arrows: Value(arrows),
        ),
        fields: {
          WireFields.fromId: from.id,
          WireFields.toId: to.id,
          WireFields.text: text,
          WireFields.color: ?color,
          WireFields.strokeWidth: ?strokeWidth,
          WireFields.line: ?line,
          WireFields.arrows: ?arrows,
        },
        containerType: EntityTypes.wikiPage,
        containerId: from.pageId,
        // Not before either end: elements go out in the order they were made, so
        // hung off the newer it follows both — and an element held back or refused
        // holds the connection back too, instead of letting it fail on its own.
        after: from.id.compareTo(to.id) > 0 ? from.id : to.id,
        alsoAfter: [from.id, to.id],
        label: text,
      ),
    );
    return given;
  }

  /// Changes a connection's label, colour, thickness, line or arrow heads — each
  /// only if given.
  Future<void> changeEdge(
    MindmapEdge edge, {
    String? text,
    Change<String?>? color,
    Change<int?>? strokeWidth,
    Change<String?>? line,
    Change<String?>? arrows,
  }) async {
    final row = MindmapEdgesCompanion(
      id: Value(edge.id),
      body: _changed(text, edge.text),
      color: _cleared(color, edge.color),
      strokeWidth: strokeWidth == null || strokeWidth.value == edge.strokeWidth
          ? const .absent()
          : .new(strokeWidth.value),
      line: _cleared(line, edge.line),
      arrows: _cleared(arrows, edge.arrows),
    );
    final fields = <String, dynamic>{
      if (row.body case Value(present: true, :final value))
        WireFields.text: value,
      if (row.color case Value(present: true, :final value))
        WireFields.color: value,
      if (row.strokeWidth case Value(present: true, :final value))
        WireFields.strokeWidth: value,
      if (row.line case Value(present: true, :final value))
        WireFields.line: value,
      if (row.arrows case Value(present: true, :final value))
        WireFields.arrows: value,
    };
    if (fields.isEmpty) return;
    await _writes.run(
      (write) => write.change(
        _db.mindmapEdges,
        row,
        id: edge.id,
        version: edge.version,
        fields: fields,
        containerType: EntityTypes.wikiPage,
        containerId: edge.pageId,
        label: text ?? edge.text,
      ),
    );
  }

  Future<void> deleteEdge(MindmapEdge edge) => _writes.run(
    (write) => write.delete(
      _db.mindmapEdges,
      id: edge.id,
      version: edge.version,
      label: edge.text,
    ),
  );

  /// A width or height as the server keeps it: from 1 to [mindmapMaxSize]. Every
  /// size an element gets passes here — resized, aligned, sized for its text, a
  /// stroke drawn across the map zoomed out — and one beyond it was refused for good.
  static int _size(int value) => value.clamp(1, mindmapMaxSize);

  /// [value] where it is given and differs from [now]; absent otherwise.
  static Value<T> _changed<T extends Object>(T? value, T? now) =>
      value == null || value == now ? const .absent() : .new(value);

  /// Like [_changed], for a field that may be cleared.
  static Value<String?> _cleared(Change<String?>? change, String? now) =>
      change == null || change.value == now
      ? const .absent()
      : .new(change.value);

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

  /// What a change is called in the list of what could not sync.
  static String _labelOf(String kind, String text) =>
      text.isEmpty ? kind : text.split('\n').first;
}

extension on MindmapNodeRow {
  MindmapNode toDomain() => .new(
    id: id,
    ownerId: ownerId,
    version: version,
    pageId: pageId,
    kind: kind,
    x: x,
    y: y,
    width: width,
    height: height,
    layer: layer,
    text: body,
    target: target,
    linkView: linkView,
    color: color,
    shape: shape,
    textSize: textSize,
    textColor: textColor,
    points: points,
    strokeWidth: strokeWidth,
    rotation: rotation,
  );
}

extension on MindmapEdgeRow {
  MindmapEdge toDomain() => .new(
    id: id,
    ownerId: ownerId,
    version: version,
    pageId: pageId,
    fromId: fromId,
    toId: toId,
    text: body,
    color: color,
    strokeWidth: strokeWidth,
    line: line,
    arrows: arrows,
  );
}
