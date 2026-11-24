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
import '../../../domain/common/item_ref.dart';
import '../../../domain/links/link_index.dart';
import '../../../domain/preferences/preferences.dart';
import '../../../domain/sync/sync_items.dart';
import '../../../domain/wiki/mindmap.dart';
import '../../../domain/wiki/mindmap_kinds.dart';
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
          if (node.traits.remembersSize)
            node.kind: (width: node.width, height: node.height),
        // … unless one was placed or resized here since.
        for (final kind in mindmapKinds)
          if (mindmapKindOf(kind).remembersSize)
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
  /// returns its id. [look] holds its other fields by their names on the wire
  /// ([MindmapNode.fields]).
  @command
  Future<String> addNode({
    required String kind,
    required ({int x, int y}) at,
    required ({int width, int height}) size,
    String text = '',
    Map<String, Object?> look = const {},
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
        look: look,
      ),
    );
    return id;
  }

  /// Remembers that an element of [kind] now is [width] × [height]: the next new
  /// one of its kind on this map takes it.
  void _sized(String kind, int width, int height) {
    if (!mindmapKindOf(kind).remembersSize) return;
    unawaited(
      ref
          .read(preferencesStoreProvider)
          .recordMindmapSize(pageId, kind, width: width, height: height),
    );
  }

  /// The way back from placing [id], and forth again.
  void _rememberPlaced(String id) {
    final maps = ref.read(mindmapRepositoryProvider);
    _Taken? taken;
    _remember(
      undo: () async => taken = await _take(maps, [id]),
      redo: () async {
        if (taken case final gone?) {
          await maps.restore(nodes: gone.nodes, edges: gone.edges);
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
  Future<void> move(Map<MindmapNode, ({int x, int y})> moves) => _changeAll({
    for (final MapEntry(key: node, value: to) in moves.entries)
      node: {WireFields.x: to.x, WireFields.y: to.y},
  });

  Future<void> resize(
    MindmapNode node, {
    required int width,
    required int height,
  }) {
    _sized(node.kind, width, height);
    return _change(node, node.changesTo(node.resizedTo(width, height)));
  }

  /// Moves and resizes several elements as one step — a group aligned, spread out
  /// or given one size: [places] holds each one's new box.
  Future<void> arrange(Map<MindmapNode, MindmapNode> places) async {
    final changed = {
      for (final MapEntry(key: node, value: to) in places.entries)
        if (node.changesTo(to) case final changes when changes.isNotEmpty)
          node: changes,
    };
    if (changed.isEmpty) return;
    for (final MapEntry(key: node, value: to) in places.entries) {
      if (to.width != node.width || to.height != node.height) {
        _sized(to.kind, to.width, to.height);
      }
    }
    await _changeAll(changed);
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
  }) => _change(node, {
    WireFields.text: text,
    WireFields.width: ?box?.width,
    WireFields.height: ?box?.height,
  });

  /// What a link element shows of its target — showing the content, it grows to at
  /// least [room], where the preview can be read.
  Future<void> setLinkView(
    MindmapNode node,
    String view, {
    required ({int width, int height}) room,
  }) {
    final content = view == MindmapLinkViews.content;
    return _change(node, {
      WireFields.linkView: view,
      if (content) WireFields.width: math.max(node.width, room.width),
      if (content) WireFields.height: math.max(node.height, room.height),
    });
  }

  /// A text size; [box] is the room the text needs at it, where the element is as
  /// large as its text.
  Future<void> setTextSize(
    MindmapNode node,
    String? size, {
    ({int width, int height})? box,
  }) => _change(node, {
    WireFields.textSize: size,
    WireFields.width: ?box?.width,
    WireFields.height: ?box?.height,
  });

  /// Gives [node] the fields in [changes] — by their names on the wire
  /// ([MindmapNode.fields]), `null` clearing one — as one step for "Undo". A field
  /// of an element's look needs nothing more here.
  Future<void> setFields(MindmapNode node, Map<String, Object?> changes) =>
      _change(node, changes);

  /// The same [changes] for a group: one step for "Undo", and each element given
  /// those fields and nothing else.
  Future<void> setFieldsOfAll(
    List<MindmapNode> nodes,
    Map<String, Object?> changes,
  ) => _changeAll({for (final node in nodes) node: changes});

  /// A stroke drawn by hand — [points] in the map's units, as the pen went — goes on
  /// the map as an element of its own, [width] thick. [look] holds what else the pen
  /// drew it with, by the fields' names on the wire — its colour, the shape it was
  /// drawn as, which makes it resizable later: a new option of the pen is a field
  /// here, nothing more.
  Future<void> draw(
    List<Offset> points, {
    required int width,
    Map<String, Object?> look = const {},
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
        look: {
          ...look,
          WireFields.points: stroke.points,
          WireFields.strokeWidth: width,
        },
      ),
    );
  }

  /// Takes the strokes a swipe of the eraser went over away — one step for "Undo".
  Future<void> erase(List<MindmapNode> strokes) => deleteAll(strokes);

  /// Takes several elements away at once — a swipe of the eraser, a group — with
  /// their connections: one step for "Undo".
  Future<void> deleteAll(List<MindmapNode> nodes) async {
    if (nodes.isEmpty) return;
    final maps = ref.read(mindmapRepositoryProvider);
    final ids = [for (final node in nodes) node.id];
    // Known once they are taken — and taken anew by every "Redo", with whatever was
    // changed or connected to them since: "Undo" runs only after that ([_inTurn]).
    _Taken? taken;
    _remember(
      undo: () async {
        if (taken case final gone?) {
          await maps.restore(nodes: gone.nodes, edges: gone.edges);
        }
      },
      redo: () async => taken = await _take(maps, ids),
    );
    await _inTurn(() async => taken = await _take(maps, ids));
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
    await _change(node, {WireFields.layer: layer});
  }

  Future<void> _change(MindmapNode node, Map<String, Object?> changes) =>
      _changeAll({node: changes});

  /// Gives each element its changes — fields by their names on the wire — and
  /// remembers the way back, all as one step.
  ///
  /// Of each, only the fields that differ from the element as stored when its turn
  /// comes are written, and only those "Undo" sets back — to what they were then:
  /// what someone else changed meanwhile in another field, or along another axis,
  /// stays as they left it. Compared there and not with the element as the screen
  /// showed it, a switch turned on and off again in a sheet that stays open writes
  /// both times, and "Undo" takes each back. Each goes out on the version the screen
  /// showed: a field someone else changed meanwhile is a conflict, not painted over.
  Future<void> _changeAll(
    Map<MindmapNode, Map<String, Object?>> changes,
  ) async {
    // The repository taken now, not when its turn comes: the screen may be closed
    // by then, and its ViewModel with it — a read then failed, and the change was
    // lost.
    final maps = ref.read(mindmapRepositoryProvider);
    // Known once written: "Undo" and "Redo" run only after that ([_inTurn]).
    final before = <String, Map<String, Object?>>{};
    final after = <String, Map<String, Object?>>{};
    Future<void> write(Map<String, Map<String, Object?>> fields) async {
      for (final MapEntry(key: id, value: changes) in fields.entries) {
        if (await maps.node(id) case final current?) {
          await maps.changeNodes({current: changes});
        }
      }
    }

    _remember(undo: () => write(before), redo: () => write(after));
    await _inTurn(() async {
      final written = <MindmapNode, Map<String, Object?>>{};
      for (final MapEntry(key: node, value: wanted) in changes.entries) {
        final stored = (await maps.node(node.id))?.fields ?? node.fields;
        final differing = {
          for (final MapEntry(key: field, :value) in wanted.entries)
            if (stored[field] != value) field: value,
        };
        if (differing.isEmpty) continue;
        before[node.id] = {
          for (final field in differing.keys) field: stored[field],
        };
        after[node.id] = differing;
        written[node] = differing;
      }
      await maps.changeNodes(written);
    });
  }

  /// Takes the element away, and its connections with it.
  Future<void> delete(MindmapNode node) => deleteAll([node]);

  /// Takes the elements [ids] away with their connections, and returns what "Undo"
  /// brings back: the elements as they are on the device when taken — not as the
  /// screen last showed them, or a text written meanwhile went back to the old one —
  /// and each connection once, however many of them it joins.
  static Future<_Taken> _take(MindmapRepository maps, List<String> ids) async {
    final nodes = [for (final id in ids) ?await maps.node(id)];
    final edges = <String, MindmapEdge>{
      for (final node in nodes)
        for (final edge in await maps.edgesAt(node.id)) edge.id: edge,
    };
    await maps.deleteNodes(nodes);
    return (nodes: nodes, edges: [...edges.values]);
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
    await _inTurn(() => maps.connect(from, to, id: id, look: made.fields));
  }

  /// Gives [edge] the fields in [changes] — its label, colour, thickness, line or
  /// arrow heads, by their names on the wire ([MindmapEdge.fields]) — as one step
  /// for "Undo", as [setFields] changes an element.
  Future<void> setEdgeFields(
    MindmapEdge edge,
    Map<String, Object?> changes,
  ) async {
    final maps = ref.read(mindmapRepositoryProvider);
    // Known once written: "Undo" and "Redo" run only after that ([_inTurn]).
    Map<String, Object?> before = {};
    Map<String, Object?> after = {};
    Future<void> write(Map<String, Object?> fields) async {
      if (fields.isEmpty) return;
      if (await maps.edge(edge.id) case final current?) {
        await maps.changeEdge(current, fields);
      }
    }

    _remember(undo: () => write(before), redo: () => write(after));
    await _inTurn(() async {
      final stored = (await maps.edge(edge.id))?.fields ?? edge.fields;
      after = {
        for (final MapEntry(key: field, :value) in changes.entries)
          if (stored[field] != value) field: value,
      };
      before = {for (final field in after.keys) field: stored[field]};
      if (after.isEmpty) return;
      await maps.changeEdge(edge, after);
    });
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
    try {
      await _inTurn(step.undo);
    } on Object {
      _putBack(step, from: _redo, to: _undo);
      rethrow;
    }
  }

  /// Does what was taken back again.
  Future<void> redo() async {
    final step = _redo.lastOrNull;
    if (step == null) return;
    _redo.removeLast();
    _undo.add(step);
    ref.invalidateSelf();
    try {
      await _inTurn(step.redo);
    } on Object {
      _putBack(step, from: _undo, to: _redo);
      rethrow;
    }
  }

  /// A step that could not be taken back, or done again, goes back where it was, so
  /// that the history says what the map shows. Moved over all the same, "Redo"
  /// offered a step that had never been taken back, and the next "Undo" skipped one
  /// still on the map and took back the one before it.
  void _putBack(
    _Step step, {
    required List<_Step> from,
    required List<_Step> to,
  }) {
    if (!from.remove(step)) return;
    to.add(step);
    if (ref.mounted) ref.invalidateSelf();
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

/// Elements taken away, and the connections that went with them.
typedef _Taken = ({List<MindmapNode> nodes, List<MindmapEdge> edges});

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
