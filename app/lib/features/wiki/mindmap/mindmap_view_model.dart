import 'dart:async';
import 'dart:math' as math;

import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/link_index.dart';
import '../../../app/repositories.dart';
import '../../../app/stores.dart';
import '../../../core/api/generated/export.dart' hide Mutation;
import '../../../core/common/command.dart';
import '../../../core/common/ids.dart';
import '../../../core/common/wire.dart';
import '../../../data/media/media_repository.dart' show ImageOwnerTypes;
import '../../../data/wiki/mindmap_repository.dart' show MindmapRepository;
import '../../../domain/access/access_rules.dart';
import '../../../domain/common/change.dart';
import '../../../domain/common/item_ref.dart';
import '../../../domain/links/link_index.dart';
import '../../../domain/preferences/preferences.dart';
import '../../../domain/sync/sync_items.dart';
import '../../../domain/wiki/mindmap.dart';
import '../../../domain/wiki/page_images.dart';
import '../../../domain/wiki/wiki_page.dart';

part 'mindmap_view_model.g.dart';

/// `addNode`, run by the canvas: it selects what it placed.
final addMindmapNodeMutation = Mutation<String>(
  label: 'mindmapViewModel.addNode',
);

/// `keepImages`, run by the canvas: it shows that pictures are being read in.
final keepMindmapImagesMutation = Mutation<String>(
  label: 'mindmapViewModel.keepImages',
);

/// A page's mind map on its own screen: the canvas, what may be done on it, what a
/// search found and what lost against someone else's change.
@immutable
class MindmapState {
  const MindmapState({
    required this.page,
    required this.map,
    required this.writable,
    required this.targets,
    required this.conflicts,
    required this.query,
    required this.hits,
    required this.index,
    this.order = .place,
    this.descending = false,
    this.members = const {},
    this.canUndo = false,
    this.canRedo = false,
    this.snap = true,
    this.grid = false,
    this.lastSizes = const {},
  });

  final WikiPage page;
  final Mindmap map;

  /// Whether what is moved or resized snaps to other elements, and whether the grid
  /// shows and is snapped to — this device's choice.
  final bool snap;
  final bool grid;

  /// The size a new element of each kind takes, by kind: the one placed or resized
  /// last on this map on this device; before that, the newest of the kind on the
  /// map.
  final Map<String, ({int width, int height})> lastSizes;

  /// Whoever may write the page edits its map; an archived page's map is read-only.
  final bool writable;

  /// What each link element points to, by its address.
  final Map<String, LinkItem> targets;

  /// The open conflicts of the map's elements and connections, by their id — each
  /// field of an element is one.
  final Map<String, List<SyncConflict>> conflicts;

  /// The search on the canvas; empty while none.
  final String query;

  /// What it found, in [order] — the other way round if [descending].
  final List<MindmapHit> hits;
  final MindmapHitOrder order;
  final bool descending;

  /// Whether a change made on this screen can be taken back, or done again.
  final bool canUndo;
  final bool canRedo;

  /// What a link element points to, as this device knows it.
  LinkItem? targetOf(String target) => targets[target];

  /// Every item this device knows by its link — where a conflict names a target the
  /// map no longer points to.
  final LinkIndex index;

  /// A link element's address by its target's title and number, a member element's
  /// by the member's name — `null` when neither is on this device.
  String? labelOfTarget(String address) =>
      targetLabelOf(address, index) ?? memberOf(address)?.displayName;

  /// The family's members, by id — whom a member element shows.
  final Map<String, Member> members;

  /// The member a member element's [target] names — `null` when they are not in the
  /// family (any more).
  Member? memberOf(String? target) => members[memberIdOf(target)];

  /// The own colours already used on this map, newest first — offered again.
  List<String> get ownColors {
    final seen = <String>{};
    final ordered = [
      for (final node in map.nodes.reversed) ...[node.color, node.textColor],
      for (final edge in map.edges.reversed) edge.color,
    ];
    return [
      for (final color in ordered)
        if (MindmapColor.parse(color) case final OwnColor own)
          if (seen.add(own.stored)) own.stored,
    ];
  }
}

@riverpod
Stream<WikiPage?> _page(Ref ref, String pageId) =>
    ref.watch(wikiRepositoryProvider).watchPage(pageId);

@riverpod
Stream<Mindmap> _map(Ref ref, String pageId) =>
    ref.watch(mindmapRepositoryProvider).watchMap(pageId);

@riverpod
Stream<ShareSheet> _shares(Ref ref, String pageId) => ref
    .watch(accessRepositoryProvider)
    .watchShareSheet(ItemRef.wikiPage(pageId));

@riverpod
Stream<List<Member>> _members(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchMembers();

@riverpod
Stream<List<SyncConflict>> _conflicts(Ref ref) =>
    ref.watch(syncRepositoryProvider).watchConflicts();

@riverpod
Stream<Uint8List> _image(Ref ref, String imageId, bool preview) =>
    ref.watch(mediaRepositoryProvider).watchImage(imageId, preview: preview);

@riverpod
class MindmapViewModel extends _$MindmapViewModel {
  String _query = '';
  MindmapHitOrder _order = .place;
  bool _descending = false;

  /// `null` once the page is gone.
  @override
  Future<MindmapState?> build(String pageId) async {
    // From the server — not waited for: offline it may never come, and the level
    // last known on this device decides meanwhile.
    final level = ref.watch(_sharesProvider(pageId)).value?.myLevel;
    // Not waited for either: a member element shows its initial until they come.
    final members = {
      for (final member
          in ref.watch(_membersProvider).value ?? const <Member>[])
        member.id: member,
    };
    final index = ref.watch(linkIndexProvider);
    final lining = ref.watch(
      preferencesProvider.select(
        (preferences) => (
          snap: preferences.mindmapSnap,
          grid: preferences.mindmapGrid,
          sizes: preferences.mindmapSizes,
        ),
      ),
    );
    final pageSource = ref.watch(_pageProvider(pageId).future);
    final mapSource = ref.watch(_mapProvider(pageId).future);
    final conflictSource = ref.watch(_conflictsProvider.future);
    final page = await pageSource;
    if (page == null || page.deletedAt != null) return null;
    final map = await mapSource;
    final conflicts = await conflictSource;
    final ids = {
      for (final node in map.nodes) node.id,
      for (final edge in map.edges) edge.id,
    };
    final targets = <String, LinkItem>{
      for (final target in [for (final node in map.nodes) ?node.target])
        target: ?linkItemOf(target, index),
    };
    return MindmapState(
      page: page,
      map: map,
      writable: mayWrite(level) && page.archivedAt == null,
      targets: targets,
      conflicts: {
        for (final conflict in conflicts)
          if (ids.contains(conflict.entityId))
            conflict.entityId: [
              for (final other in conflicts)
                if (other.entityId == conflict.entityId) other,
            ],
      },
      query: _query,
      hits: sortHits(
        searchMindmap(
          map,
          _query,
          titleOf: (target) =>
              targets[target]?.title ??
              members[memberIdOf(target)]?.displayName,
        ),
        _order,
        descending: _descending,
      ),
      order: _order,
      descending: _descending,
      index: index,
      members: members,
      canUndo: _undo.isNotEmpty,
      canRedo: _redo.isNotEmpty,
      snap: lining.snap,
      grid: lining.grid,
      lastSizes: {
        // The newest of each kind — ids are made in time order …
        for (final node in [...map.nodes]..sort((a, b) => a.id.compareTo(b.id)))
          if (MindmapKinds.sized.contains(node.kind))
            node.kind: (width: node.width, height: node.height),
        // … unless one was placed or resized here since.
        for (final kind in MindmapKinds.sized)
          kind: ?lining.sizes[Preferences.mindmapSizeKey(pageId, kind)],
      },
    );
  }

  /// Searches the canvas — empty ends the search.
  void search(String query) {
    _query = query;
    ref.invalidateSelf();
  }

  /// Puts what the search found in [order], the other way round if [descending].
  void orderHits({required MindmapHitOrder order, required bool descending}) {
    _order = order;
    _descending = descending;
    ref.invalidateSelf();
  }

  /// Places a new element at [at] — its top left corner, in the map's units — and
  /// returns its id.
  @command
  Future<String> addNode({
    required String kind,
    required ({int x, int y}) at,
    required ({int width, int height}) size,
    String text = '',
    String? target,
    String? linkView,
  }) async {
    final maps = ref.read(mindmapRepositoryProvider);
    final id = newId();
    _rememberPlaced(id);
    _sized(kind, size.width, size.height);
    await _inTurn(
      () => maps.addNode(
        id: id,
        pageId: pageId,
        kind: kind,
        x: at.x,
        y: at.y,
        width: size.width,
        height: size.height,
        text: text,
        target: target,
        linkView: linkView,
      ),
    );
    return id;
  }

  /// Remembers that an element of [kind] now is [width] × [height]: the next new
  /// one of its kind on this map takes it.
  void _sized(String kind, int width, int height) {
    if (!MindmapKinds.sized.contains(kind)) return;
    unawaited(
      ref
          .read(preferencesStoreProvider)
          .recordMindmapSize(pageId, kind, width: width, height: height),
    );
  }

  /// The way back from placing [id], and forth again.
  void _rememberPlaced(String id) {
    final maps = ref.read(mindmapRepositoryProvider);
    _remember(
      undo: () async {
        if (await maps.node(id) case final node?) await _deleteWithEdges(node);
      },
      redo: () async {
        final again = _deleted[id];
        if (again != null) {
          await maps.restore(nodes: [again.node], edges: again.edges);
        }
      },
    );
  }

  /// Keeps pictures on the device for this page and returns them as the Markdown a
  /// picture element holds — they go up with the sync, after the page; offline too.
  @command
  Future<String> keepImages(
    List<({Uint8List bytes, String filename})> files,
  ) async {
    final media = ref.read(mediaRepositoryProvider);
    final ids = [
      for (final file in files)
        await media.keep(
          ownerType: ImageOwnerTypes.wikiPage,
          ownerItemId: pageId,
          bytes: file.bytes,
          filename: file.filename,
        ),
    ];
    return imagesInsertion('', 0, ids).trim();
  }

  /// Moves elements dragged together, each to its new top left corner.
  Future<void> move(Map<MindmapNode, ({int x, int y})> moves) async {
    final maps = ref.read(mindmapRepositoryProvider);
    final steps = [
      for (final MapEntry(key: node, value: to) in moves.entries)
        (from: node, to: node.changed(x: to.x, y: to.y)),
    ];
    _remember(
      undo: () => _place(maps, [
        for (final step in steps) (from: step.to, to: step.from),
      ]),
      redo: () => _place(maps, steps),
    );
    await _inTurn(() => ref.read(mindmapRepositoryProvider).moveNodes(moves));
  }

  /// Puts each element of [steps] where `to` has it — in the place and size it
  /// differs from `from` in, and nothing else: what someone else moved or resized
  /// meanwhile along another axis stays as they left it.
  static Future<void> _place(
    MindmapRepository maps,
    List<({MindmapNode from, MindmapNode to})> steps,
  ) async {
    final places = <MindmapNode, ({int x, int y, int width, int height})>{};
    for (final (:from, :to) in steps) {
      final current = await maps.node(to.id);
      if (current == null) continue;
      places[current] = (
        x: to.x != from.x ? to.x : current.x,
        y: to.y != from.y ? to.y : current.y,
        width: to.width != from.width ? to.width : current.width,
        height: to.height != from.height ? to.height : current.height,
      );
    }
    await maps.arrangeNodes(places);
  }

  Future<void> resize(
    MindmapNode node, {
    required int width,
    required int height,
  }) {
    _sized(node.kind, width, height);
    return _change(node, node.resizedTo(width, height));
  }

  /// Moves and resizes several elements as one step — a group aligned, spread out
  /// or given one size: [places] holds each one's new box.
  Future<void> arrange(Map<MindmapNode, MindmapNode> places) async {
    final changed = {
      for (final MapEntry(key: node, value: to) in places.entries)
        if (to.x != node.x ||
            to.y != node.y ||
            to.width != node.width ||
            to.height != node.height)
          node: to,
    };
    if (changed.isEmpty) return;
    final maps = ref.read(mindmapRepositoryProvider);
    final steps = [
      for (final MapEntry(key: node, value: to) in changed.entries)
        (from: node, to: to),
    ];
    _remember(
      undo: () => _place(maps, [
        for (final step in steps) (from: step.to, to: step.from),
      ]),
      redo: () => _place(maps, steps),
    );
    for (final MapEntry(key: node, value: to) in changed.entries) {
      if (to.width != node.width || to.height != node.height) {
        _sized(to.kind, to.width, to.height);
      }
    }
    await _inTurn(
      () => maps.arrangeNodes({
        for (final MapEntry(key: node, value: to) in changed.entries)
          node: (x: to.x, y: to.y, width: to.width, height: to.height),
      }),
    );
  }

  /// Whether what is moved or resized snaps to other elements, on this device.
  void setSnap(bool snap) =>
      unawaited(ref.read(preferencesStoreProvider).setMindmapSnap(snap));

  /// Whether the grid shows and is snapped to, on this device.
  void setGrid(bool grid) =>
      unawaited(ref.read(preferencesStoreProvider).setMindmapGrid(grid));

  /// A new text; [box] is the element's size for it — the room a plain snippet's
  /// text needs, a picture's shape.
  Future<void> setText(
    MindmapNode node,
    String text, {
    ({int width, int height})? box,
  }) => _change(
    node,
    node.changed(text: text, width: box?.width, height: box?.height),
  );

  Future<void> setTarget(MindmapNode node, String target) =>
      _change(node, node.styled(target: Change(target)));

  /// What a link element shows of its target — showing the content, it grows to at
  /// least [room], where the preview can be read.
  Future<void> setLinkView(
    MindmapNode node,
    String view, {
    required ({int width, int height}) room,
  }) {
    final content = view == MindmapLinkViews.content;
    return _change(
      node,
      node
          .styled(linkView: Change(view))
          .changed(
            width: content ? math.max(node.width, room.width) : null,
            height: content ? math.max(node.height, room.height) : null,
          ),
    );
  }

  Future<void> setColor(MindmapNode node, String? color) =>
      _change(node, node.styled(color: Change(color)));

  /// One colour for a group: one step for "Undo".
  ///
  /// The colour and nothing else: [nodes] are the elements as the corner showed
  /// them, and written whole they put back what anyone had changed since in any
  /// other field. "Undo" gives each the colour it had when this was written.
  Future<void> setColors(List<MindmapNode> nodes, String? color) async {
    final maps = ref.read(mindmapRepositoryProvider);
    const fields = {WireFields.color};
    // Known once written: "Undo" runs only after that ([_inTurn]).
    final before = <String, String?>{};
    Future<void> paint(String? Function(String id) colorOf) async {
      for (final id in before.keys) {
        if (await maps.node(id) case final current?) {
          await _write(
            maps,
            current,
            current.styled(color: Change(colorOf(id))),
            fields,
          );
        }
      }
    }

    _remember(
      undo: () => paint((id) => before[id]),
      redo: () => paint((_) => color),
    );
    await _inTurn(() async {
      for (final node in nodes) {
        final current = await maps.node(node.id);
        if (current == null) continue;
        before[node.id] = current.color;
        // On the version the corner showed: a colour someone else chose meanwhile
        // is a conflict, not silently painted over.
        await _write(maps, node, node.styled(color: Change(color)), fields);
      }
    });
  }

  Future<void> setShape(MindmapNode node, String? shape) =>
      _change(node, node.styled(shape: Change(shape)));

  /// A text size; [box] is the room the text needs at it, where the element is as
  /// large as its text.
  Future<void> setTextSize(
    MindmapNode node,
    String? size, {
    ({int width, int height})? box,
  }) => _change(
    node,
    node
        .styled(textSize: Change(size))
        .changed(width: box?.width, height: box?.height),
  );

  Future<void> setTextColor(MindmapNode node, String? color) =>
      _change(node, node.styled(textColor: Change(color)));

  Future<void> setStrokeWidth(MindmapNode node, int width) =>
      _change(node, node.styled(strokeWidth: Change(width)));

  /// Turns [node] to [rotation] whole degrees clockwise — `null`: not turned — as one
  /// step for "Undo", however long the grip was turned.
  Future<void> setRotation(MindmapNode node, int? rotation) =>
      _change(node, node.styled(rotation: Change(rotation)));

  /// A stroke drawn by hand — [points] in the map's units, as the pen went — goes on
  /// the map as an element of its own, in [color] and [width] thick; drawn as
  /// [shape], it may be resized later.
  Future<void> draw(
    List<Offset> points, {
    required String? color,
    required int width,
    String? shape,
  }) async {
    final stroke = strokeOf(points, width.toDouble());
    final maps = ref.read(mindmapRepositoryProvider);
    final id = newId();
    _rememberPlaced(id);
    await _inTurn(
      () => maps.addNode(
        id: id,
        pageId: pageId,
        kind: MindmapKinds.drawing,
        x: stroke.bounds.left.round(),
        y: stroke.bounds.top.round(),
        width: math.max(1, stroke.bounds.width.round()),
        height: math.max(1, stroke.bounds.height.round()),
        color: color,
        shape: shape,
        points: stroke.points,
        strokeWidth: width,
      ),
    );
  }

  /// Takes the strokes a swipe of the eraser went over away — one step for "Undo".
  Future<void> erase(List<MindmapNode> strokes) => deleteAll(strokes);

  /// Takes several elements away at once — a swipe of the eraser, a group — with
  /// their connections: one step for "Undo".
  Future<void> deleteAll(List<MindmapNode> strokes) async {
    if (strokes.isEmpty) return;
    final maps = ref.read(mindmapRepositoryProvider);
    // Known once they are taken: "Undo" runs only after that ([_inTurn]).
    List<({MindmapNode node, List<MindmapEdge> edges})> gone = const [];
    _remember(
      undo: () => maps.restore(
        nodes: [for (final each in gone) each.node],
        edges: [for (final each in gone) ...each.edges],
      ),
      redo: () async {
        final current = [
          for (final stroke in strokes) ?await maps.node(stroke.id),
        ];
        await maps.deleteNodes(current);
      },
    );
    await _inTurn(() async {
      gone = [
        for (final stroke in strokes)
          (node: stroke, edges: await maps.edgesAt(stroke.id)),
      ];
      await maps.deleteNodes(strokes);
    });
  }

  /// One step up, past the next element overlapping it.
  Future<void> raise(MindmapNode node) => _layer(node, layerUp);

  /// One step down, below the next element overlapping it.
  Future<void> lower(MindmapNode node) => _layer(node, layerDown);

  Future<void> toFront(MindmapNode node) => _layer(node, layerToFront);

  Future<void> toBack(MindmapNode node) => _layer(node, layerToBack);

  Future<void> _layer(
    MindmapNode node,
    double? Function(Mindmap map, MindmapNode node) rule,
  ) async {
    final layer = rule(_now, node);
    if (layer == null) return;
    await _change(node, node.changed(layer: layer));
  }

  /// Writes [after] over [before] and remembers the way back — in the fields the
  /// change makes, and only those.
  Future<void> _change(MindmapNode before, MindmapNode after) async {
    final maps = ref.read(mindmapRepositoryProvider);
    final fields = before.fieldsChangedTo(after);
    _remember(
      undo: () async {
        if (await maps.node(before.id) case final node?) {
          await _write(maps, node, before, fields);
        }
      },
      redo: () async {
        if (await maps.node(after.id) case final node?) {
          await _write(maps, node, after, fields);
        }
      },
    );
    await _inTurn(() => _write(maps, before, after, fields));
  }

  /// Changes [node] to look as [to] does in [fields] — of those, only what differs
  /// goes out. "Undo" and "Redo" write on the element as it is now, on its latest
  /// version: written whole, they put back what someone else had changed meanwhile
  /// in a field the step never touched, and without a conflict.
  static Future<void> _write(
    MindmapRepository maps,
    MindmapNode node,
    MindmapNode to,
    Set<String> fields,
  ) {
    T? only<T>(String field, T value) => fields.contains(field) ? value : null;
    Change<T>? change<T>(String field, T value) =>
        fields.contains(field) ? .new(value) : null;
    return maps.changeNode(
      node,
      x: only(WireFields.x, to.x),
      y: only(WireFields.y, to.y),
      width: only(WireFields.width, to.width),
      height: only(WireFields.height, to.height),
      layer: only(WireFields.layer, to.layer),
      text: only(WireFields.text, to.text),
      target: only<String?>(WireFields.target, to.target),
      linkView: change(WireFields.linkView, to.linkView),
      color: change(WireFields.color, to.color),
      shape: change(WireFields.shape, to.shape),
      textSize: change(WireFields.textSize, to.textSize),
      textColor: change(WireFields.textColor, to.textColor),
      strokeWidth: change(WireFields.strokeWidth, to.strokeWidth),
      rotation: change(WireFields.rotation, to.rotation),
    );
  }

  /// Takes the element away, and its connections with it.
  Future<void> delete(MindmapNode node) async {
    _remember(
      undo: () async {
        final gone = _deleted[node.id];
        if (gone != null) {
          await ref
              .read(mindmapRepositoryProvider)
              .restore(nodes: [gone.node], edges: gone.edges);
        }
      },
      redo: () async {
        final current = await ref.read(mindmapRepositoryProvider).node(node.id);
        if (current != null) await _deleteWithEdges(current);
      },
    );
    await _inTurn(() => _deleteWithEdges(node));
  }

  /// What was deleted, with the connections that went along — what "Undo" brings
  /// back.
  final _deleted = <String, ({MindmapNode node, List<MindmapEdge> edges})>{};

  Future<void> _deleteWithEdges(MindmapNode node) async {
    final maps = ref.read(mindmapRepositoryProvider);
    _deleted[node.id] = (node: node, edges: await maps.edgesAt(node.id));
    await maps.deleteNode(node);
  }

  /// Connects [from] to [to] with a line of [line] and heads at [arrows] — both
  /// `null`: a plain line — in [color] and [strokeWidth] (`null`: the app's own).
  Future<void> connect(
    MindmapNode from,
    MindmapNode to, {
    String? line,
    String? arrows,
    String? color,
    int? strokeWidth,
  }) async {
    final maps = ref.read(mindmapRepositoryProvider);
    final id = newId();
    final made = MindmapEdge(
      id: id,
      ownerId: from.ownerId,
      version: 0,
      pageId: from.pageId,
      fromId: from.id,
      toId: to.id,
      text: '',
      line: line,
      arrows: arrows,
      color: color,
      strokeWidth: strokeWidth,
    );
    _remember(
      undo: () async {
        if (await maps.edge(id) case final edge?) await maps.deleteEdge(edge);
      },
      redo: () => maps.restore(edges: [made]),
    );
    await _inTurn(
      () => maps.connect(
        from,
        to,
        id: id,
        line: line,
        arrows: arrows,
        color: color,
        strokeWidth: strokeWidth,
      ),
    );
  }

  Future<void> setEdgeText(MindmapEdge edge, String text) =>
      _changeEdge(edge, _lookOf(edge).withText(text));

  Future<void> setEdgeColor(MindmapEdge edge, String? color) =>
      _changeEdge(edge, _lookOf(edge).withColor(color));

  /// How thick a connection is drawn, in the map's units; `null`: the app's own.
  Future<void> setEdgeWidth(MindmapEdge edge, int? width) =>
      _changeEdge(edge, _lookOf(edge).withWidth(width));

  /// How a connection is drawn: its line and its arrow heads, as one step.
  Future<void> setEdgeStyle(
    MindmapEdge edge, {
    required String? line,
    required String? arrows,
  }) => _changeEdge(edge, _lookOf(edge).withStyle(line, arrows));

  static _EdgeLook _lookOf(MindmapEdge edge) => (
    text: edge.text,
    color: edge.color,
    width: edge.strokeWidth,
    line: edge.line,
    arrows: edge.arrows,
  );

  /// Gives [edge] the [look] and remembers the way back — in what the change makes,
  /// and only that: a label someone else wrote meanwhile stays when the colour is
  /// taken back.
  Future<void> _changeEdge(MindmapEdge edge, _EdgeLook look) async {
    final maps = ref.read(mindmapRepositoryProvider);
    final before = _lookOf(edge);
    final text = look.text != before.text;
    final color = look.color != before.color;
    final width = look.width != before.width;
    final line = look.line != before.line;
    final arrows = look.arrows != before.arrows;
    Future<void> set(MindmapEdge? current, _EdgeLook look) async {
      if (current == null) return;
      await maps.changeEdge(
        current,
        text: text ? look.text : null,
        color: color ? Change(look.color) : null,
        strokeWidth: width ? Change(look.width) : null,
        line: line ? Change(look.line) : null,
        arrows: arrows ? Change(look.arrows) : null,
      );
    }

    _remember(
      undo: () async => set(await maps.edge(edge.id), before),
      redo: () async => set(await maps.edge(edge.id), look),
    );
    await _inTurn(() => set(edge, look));
  }

  Future<void> deleteEdge(MindmapEdge edge) async {
    final maps = ref.read(mindmapRepositoryProvider);
    _remember(
      undo: () => maps.restore(edges: [edge]),
      redo: () async {
        if (await maps.edge(edge.id) case final current?) {
          await maps.deleteEdge(current);
        }
      },
    );
    await _inTurn(() => maps.deleteEdge(edge));
  }

  // --- Undo and redo ---------------------------------------------------------------

  /// What was done on this screen, newest last — taken back and done again by writing
  /// the earlier or later state, as any change is written: offline too, and a field
  /// someone else changed meanwhile is a conflict like any other.
  final _undo = <_Step>[];
  final _redo = <_Step>[];

  /// The map as this device shows it now.
  Mindmap get _now => state.value?.map ?? .empty;

  void _remember({required AsyncCallback undo, required AsyncCallback redo}) {
    _undo.add(_Step(undo: undo, redo: redo));
    if (_undo.length > _steps) _undo.removeAt(0);
    _redo.clear();
    ref.invalidateSelf();
  }

  /// Takes the last change back.
  Future<void> undo() async {
    final step = _undo.lastOrNull;
    if (step == null) return;
    _undo.removeLast();
    _redo.add(step);
    ref.invalidateSelf();
    await _inTurn(step.undo);
  }

  /// Does what was taken back again.
  Future<void> redo() async {
    final step = _redo.lastOrNull;
    if (step == null) return;
    _redo.removeLast();
    _undo.add(step);
    ref.invalidateSelf();
    await _inTurn(step.redo);
  }

  /// Runs [write] once every write before it is done. A change is remembered before
  /// it is written — "Undo" right after it finds it, where it found the step before
  /// — and taken back only once it is written: read before, it would undo nothing,
  /// and the change would land after it.
  Future<T> _inTurn<T>(Future<T> Function() write) {
    final done = _turn.then((_) => write());
    // The next waits for this one, failed or not: a failure is its caller's.
    _turn = done.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return done;
  }

  Future<void> _turn = Future<void>.value();

  /// How far back "Undo" reaches — a session's worth of editing.
  static const _steps = 100;

  /// "Take mine": the device's own version of each field goes out once more, now on
  /// the state that caused the conflict — a decision, no longer a race.
  Future<void> takeMine(List<SyncConflict> conflicts) async {
    final sync = ref.read(syncRepositoryProvider);
    for (final conflict in conflicts) {
      await sync.takeMine(conflict);
    }
  }

  /// "Keep theirs": seen, and what the others wrote stays.
  Future<void> keepTheirs(List<SyncConflict> conflicts) async {
    final sync = ref.read(syncRepositoryProvider);
    for (final conflict in conflicts) {
      await sync.dismissConflict(conflict);
    }
  }
}

/// One change, and the ways back and forth.
class const _Step({
  required final AsyncCallback undo,
  required final AsyncCallback redo,
});

/// A picture of the map, in memory only while it is shown.
@riverpod
class MindmapImageViewModel extends _$MindmapImageViewModel {
  @override
  Future<Uint8List> build(String imageId, bool preview) =>
      ref.watch(_imageProvider(imageId, preview).future);
}

/// What a connection looks like — all a change to it sets, and an undo sets back.
typedef _EdgeLook = ({
  String text,
  String? color,
  int? width,
  String? line,
  String? arrows,
});

extension on _EdgeLook {
  _EdgeLook withText(String text) =>
      (text: text, color: color, width: width, line: line, arrows: arrows);
  _EdgeLook withColor(String? color) =>
      (text: text, color: color, width: width, line: line, arrows: arrows);
  _EdgeLook withWidth(int? width) =>
      (text: text, color: color, width: width, line: line, arrows: arrows);
  _EdgeLook withStyle(String? line, String? arrows) =>
      (text: text, color: color, width: width, line: line, arrows: arrows);
}
