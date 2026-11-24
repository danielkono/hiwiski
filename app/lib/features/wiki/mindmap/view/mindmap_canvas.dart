import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/common/wire.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../domain/common/change.dart';
import '../../../../domain/wiki/mindmap.dart';
import '../../../../domain/wiki/mindmap_snap.dart';
import '../../view/mindmap/mindmap_scene.dart';
import '../mindmap_view_model.dart';
import 'mindmap_camera.dart';
import 'mindmap_grid.dart';

/// A snippet of text being written on the canvas: the element as it is drawn now — as
/// large as what is typed — the field it is typed in, and whether it is new, not yet
/// on the map.
@immutable
class const MindmapWriting({
  required final MindmapNode node,
  required final Widget field,
  required final bool isNew,
});

/// What a finger does on the canvas while editing: select and move, draw a stroke
/// or a shape, erase the strokes it goes over, select a group with a lasso or a
/// rectangle, or connect elements.
enum MindmapTool { select, pen, shape, eraser, lasso, rectangle, connect }

/// What the pen draws with: its colour on the canvas and how thick it is on screen.
typedef MindmapPen = ({Color color, double width});

/// What is selected on the canvas: an element or a connection.
@immutable
class MindmapSelection {
  const MindmapSelection.node(this.id) : edge = false;

  const MindmapSelection.edge(this.id) : edge = true;

  final String id;
  final bool edge;

  @override
  bool operator ==(Object other) =>
      other is MindmapSelection && other.id == id && other.edge == edge;

  @override
  int get hashCode => Object.hash(id, edge);
}

/// The canvas: the map drawn under the [camera], moved and zoomed by hand — fingers,
/// a trackpad, the wheel (with Ctrl or ⌘ it zooms) — and, while [editing], its
/// elements dragged, resized and connected.
///
/// It keeps only what a gesture holds while it runs: where a dragged element is, the
/// line being drawn. What a gesture decides goes out through the callbacks when it
/// ends — one change per gesture, not one per frame.
class MindmapCanvas extends StatefulWidget {
  const MindmapCanvas({
    super.key,
    required this.state,
    required this.camera,
    required this.editing,
    required this.selection,
    required this.found,
    required this.onSelect,
    required this.onOpen,
    required this.onMove,
    required this.onResize,
    required this.onRotate,
    required this.onConnect,
    required this.onDrop,
    required this.onReady,
    this.mine,
    this.labels,
    this.writing,
    this.held = const [],
    this.tool = .select,
    this.hideDrawings = false,
    this.snap = false,
    this.grid = false,
    this.pen,
    this.penShape = .rectangle,
    this.linkStyle,
    this.linkLook,
    this.onDraw,
    this.onErase,
    this.group = const {},
    this.onGroup,
  });

  final MindmapState state;
  final MindmapCamera camera;
  final bool editing;
  final MindmapSelection? selection;

  /// What the search found, drawn above the rest.
  final Set<String> found;

  /// A tap selected something, or nothing (`null`).
  final ValueChanged<MindmapSelection?> onSelect;

  /// An element is opened: its target followed, its picture shown — or, while
  /// editing, its content edited.
  final ValueChanged<MindmapNode> onOpen;

  /// Elements moved together — one, or a group — each to its new corner.
  final ValueChanged<Map<MindmapNode, ({int x, int y})>> onMove;
  final void Function(MindmapNode node, ({int width, int height}) size)
  onResize;
  final void Function(MindmapNode from, MindmapNode to) onConnect;

  /// An element was turned by its knob to [rotation] whole degrees — `null`: not
  /// turned.
  final void Function(MindmapNode node, int? rotation) onRotate;

  /// A tool from the bar was dropped at [at], a point of the map.
  final void Function(String kind, Offset at) onDrop;

  /// The canvas has its size: the camera can be pointed at the map.
  final VoidCallback onReady;

  /// An element in conflict as this device wrote it, shown beside the map's version
  /// ([MindmapScene.mine]), and what the two are called.
  final MindmapNode? mine;
  final ({String mine, String theirs})? labels;

  /// A snippet being written here, in place.
  final MindmapWriting? writing;

  /// Elements as they were just written, drawn so until the map has them — a new
  /// text, a stroke just drawn.
  final List<MindmapNode> held;

  /// What a finger does while editing.
  final MindmapTool tool;

  /// Whether the strokes drawn by hand are out of sight — to see what lies under them.
  final bool hideDrawings;

  /// Whether what is moved or resized snaps to other elements, and whether the grid
  /// shows and is snapped to.
  final bool snap;
  final bool grid;

  /// What [MindmapTool.pen] draws with — and [MindmapTool.shape], the shape it
  /// draws.
  final MindmapPen? pen;
  final MindmapPenShape penShape;

  /// How [MindmapTool.connect] draws its connections — its kind, colour and
  /// thickness — shown so while one is drawn.
  final MindmapEdgeStyle? linkStyle;
  final ({String? color, int? width})? linkLook;

  /// A stroke was drawn: its points in the map's units, thinned out.
  final void Function(List<Offset> points, MindmapPenShape? shape)? onDraw;

  /// A swipe of the eraser went over these strokes — hidden at once, they go when
  /// the swipe ends.
  final ValueChanged<Set<String>>? onErase;

  /// Elements selected together: framed, and moved as one.
  final Set<String> group;

  /// A lasso or a rectangle went round these elements.
  final ValueChanged<Set<String>>? onGroup;

  @override
  State<MindmapCanvas> createState() => _MindmapCanvasState();
}

class _MindmapCanvasState extends State<MindmapCanvas>
    with SingleTickerProviderStateMixin {
  /// Where elements are while a gesture moves or resizes them.
  final _moving = <String, MindmapNode>{};

  /// Where a gesture left elements, by id — with the element as it was before: shown
  /// so until the change comes back from the database. Let go of at once, the element
  /// stood at its old place for a frame or two, and flickered.
  final _settling = <String, ({MindmapNode from, MindmapNode to})>{};
  final _settleLimits = <String, Timer>{};

  /// Where a drag started, so the element follows the pointer exactly.
  Offset? _grab;

  /// What the element being moved or resized lines up with right now.
  MindmapGuides? _guides;

  /// The connection being drawn: from which element, to where the pointer is.
  (MindmapNode, Offset)? _drawing;

  /// Connecting: the element the finger came down on, and where.
  ({MindmapNode node, Offset at})? _linkDown;

  /// Connecting: the element the next connection begins at — the one last tapped or
  /// reached, so that a chain is drawn on, element by element.
  String? _linkFrom;

  double _startScale = 1;
  Offset _startOrigin = .zero;
  Offset _startFocal = .zero;

  /// What the hand draws or erases right now — repainted with every move without
  /// building the map anew: rebuilt for each point, the stroke lagged behind the
  /// finger.
  final _hand = MindmapHand();

  /// The strokes this swipe of the eraser took.
  final _swept = <String>{};

  /// Strokes erased and hidden until they are gone from the map.
  final _erased = <String>{};

  /// How many fingers are on the canvas, and whether more than one has been since
  /// the first came down: then it is a pinch, and nothing is drawn until all are up.
  int _fingers = 0;
  bool _several = false;

  /// Whether the gesture under way moves the map.
  bool _panning = false;

  /// The last tap of one finger: where and when it came down — a second one there
  /// soon after, dragged, zooms.
  ({Duration time, Offset at})? _lastTap;

  /// Where the finger now down came down, and when.
  ({Duration time, Offset at})? _down;

  /// Zooming with one finger, tapped twice and dragged: where it came down, and the
  /// scale then.
  ({Offset focal, double y, double scale})? _zooming;

  final _area = GlobalKey();

  MindmapCamera get _camera => widget.camera;

  @override
  void initState() {
    super.initState();
    _camera.attach(this);
  }

  @override
  void didUpdateWidget(MindmapCanvas old) {
    super.didUpdateWidget(old);
    if (old.camera != widget.camera) {
      old.camera.detach(this);
      widget.camera.attach(this);
    }
    // Gone from the map: nothing left to hide — and back with "Undo", shown again.
    _erased.removeWhere((id) => widget.state.map.node(id) == null);
    // Moved or resized in the map: the map shows it. Held on, "Undo" — putting it
    // back as it was — brought the held place back as well.
    _settling.removeWhere(
      (id, settling) => widget.state.map.node(id) != settling.from,
    );
    // The connecting put down, or its element gone: no chain goes on from it.
    if (widget.tool != .connect ||
        widget.state.map.node(_linkFrom ?? '') == null) {
      _linkFrom = null;
      if (widget.tool != .connect && _linkDown == null) _drawing = null;
    }
  }

  @override
  void dispose() {
    for (final limit in _settleLimits.values) {
      limit.cancel();
    }
    _hand.dispose();
    widget.camera.detach(this);
    super.dispose();
  }

  /// Shows [to] for [from] until the element changes in the map — the change
  /// written, or someone else's — or, should nothing be written after all, until a
  /// moment has passed.
  void _settle(MindmapNode from, MindmapNode to) {
    _settling[from.id] = (from: from, to: to);
    _settleLimits.remove(from.id)?.cancel();
    _settleLimits[from.id] = Timer(_settleLimit, () {
      if (!mounted) return;
      setState(() => _settling.remove(from.id));
      _settleLimits.remove(from.id);
    });
  }

  static const _settleLimit = Duration(milliseconds: 600);

  /// The point of the map under a global position.
  Offset _sceneAt(Offset global) {
    final box = _area.currentContext?.findRenderObject();
    final local = box is RenderBox ? box.globalToLocal(global) : global;
    return _camera.toScene(local);
  }

  /// Whether one finger draws or erases rather than moving the map.
  bool get _byHand =>
      widget.editing && widget.state.writable && widget.tool != .select;

  // By hand, a finger draws from the moment it comes down — from its own events,
  // not from a gesture: one is recognised only once the finger has gone some way,
  // and the stroke showed half a second late.

  void _fingerDown(PointerDownEvent event) {
    if (_fingers == 0) _several = false;
    _fingers++;
    if (_fingers > 1) {
      // A second finger: a pinch. The stroke begun is let go, and what the eraser
      // took comes back.
      _several = true;
      _endByHand(keep: false);
      return;
    }
    final mouse = event.kind == .mouse;
    _down = (time: event.timeStamp, at: event.position);
    // A second tap of a finger, dragged up or down, zooms — as in a map app.
    if (event.kind == .touch && !_byHand && _emptyAt(event.position)) {
      final last = _lastTap;
      if (last != null &&
          event.timeStamp - last.time <= kDoubleTapTimeout &&
          (event.position - last.at).distance <= kDoubleTapSlop) {
        _zooming = (
          focal: event.localPosition,
          y: event.position.dy,
          scale: _camera.scale,
        );
        _lastTap = null;
        return;
      }
    }
    if (!_byHand ||
        event.kind == .trackpad ||
        (mouse && event.buttons != kPrimaryButton)) {
      return;
    }
    final at = _sceneAt(event.position);
    if (widget.tool == .shape) {
      final pen = widget.pen;
      final width = (pen?.width ?? 1) / _camera.scale;
      _hand.shape(
        at,
        widget.penShape,
        color: pen?.color ?? Colors.transparent,
        width: width,
        head: math.max(
          width * _headPerWidth,
          HiwiskiMetrics.mindmapArrowHead * 2 / _camera.scale,
        ),
      );
      return;
    }
    if (widget.tool == .connect) {
      final node = _nodeAt(at);
      _linkDown = node == null ? null : (node: node, at: at);
      // Down beside every element: the chain ends.
      if (node == null) {
        setState(() {
          _linkFrom = null;
          _drawing = null;
        });
      }
      return;
    }
    if (widget.tool case .lasso || .rectangle) {
      _hand.select(at, rectangle: widget.tool == .rectangle);
      return;
    }
    if (widget.tool == .pen) {
      _hand.draw(
        at,
        color: widget.pen?.color ?? Colors.transparent,
        width: (widget.pen?.width ?? 1) / _camera.scale,
      );
    } else {
      _hand.erase(at, radius: _eraserReach / _camera.scale);
      _eraseAlong();
    }
  }

  void _fingerMove(PointerMoveEvent event) {
    if (_zooming case final zoom? when !_several) {
      // Down zooms in, up out; the point first touched stays under the finger.
      final scale =
          (zoom.scale * math.exp((event.position.dy - zoom.y) / _zoomDrag))
              .clamp(MindmapCamera.minScale, MindmapCamera.maxScale);
      final anchor = (zoom.focal - _camera.origin) / _camera.scale;
      _camera.set(scale, zoom.focal - anchor * scale);
      return;
    }
    if (_linkDown case final down? when !_several) {
      _followEdge(event.position);
      setState(() => _drawing = (down.node, _sceneAt(event.position)));
      return;
    }
    if (!_hand.active || _several) return;
    final at = _sceneAt(event.position);
    switch (_hand.mode) {
      case .draw || .lasso || .rectangle || .shape:
        // A point a screen pixel on at least: a hand at rest adds nothing.
        if ((at - _hand.last).distance * _camera.scale >= 1) _hand.add(at);
      case .erase:
        _hand.add(at);
        _eraseAlong();
    }
  }

  void _fingerUp(PointerEvent event) {
    _fingers = math.max(0, _fingers - 1);
    if (_fingers > 0) return;
    final keep = !_several && event is PointerUpEvent;
    final down = _down;
    _down = null;
    if (_zooming != null) {
      _zooming = null;
      return;
    }
    // A short tap where it came down, on the map itself: the first of two, perhaps.
    _lastTap =
        keep &&
            event.kind == .touch &&
            down != null &&
            _emptyAt(down.at) &&
            event.timeStamp - down.time <= kLongPressTimeout &&
            (event.position - down.at).distance <= kTouchSlop
        ? down
        : null;
    _endLink(keep: keep, at: _sceneAt(event.position));
    _endByHand(keep: keep);
  }

  /// With a mouse, the next connection follows the pointer from the element it
  /// begins at.
  void _hover(PointerHoverEvent event) {
    final from = widget.state.map.node(_linkFrom ?? '');
    if (widget.tool != .connect || from == null) return;
    setState(() => _drawing = (from, _sceneAt(event.position)));
  }

  /// Ends what a finger did while connecting: dragged from one element to another,
  /// they are connected; tapped, an element is connected to the one the chain is at.
  /// Either way, the chain goes on from the element reached.
  void _endLink({required bool keep, required Offset at}) {
    final down = _linkDown;
    _linkDown = null;
    if (down == null) return;
    final dragged = (at - down.at).distance * _camera.scale >= kTouchSlop;
    setState(() => _drawing = null);
    if (!keep) return;
    final map = widget.state.map;
    final from = dragged ? down.node : map.node(_linkFrom ?? '');
    final to = dragged ? _nodeAt(at, except: down.node.id) : down.node;
    if (from != null && to != null && from.id != to.id) {
      widget.onConnect(from, to);
    }
    setState(() => _linkFrom = (to ?? down.node).id);
  }

  /// Ends a stroke or a swipe of the eraser — kept if [keep]; otherwise the stroke
  /// is dropped and what the eraser took comes back. A tap is a dot, or takes what
  /// it touches.
  void _endByHand({required bool keep}) {
    if (!_hand.active) return;
    final mode = _hand.mode;
    final points = [..._hand.points];
    final outline = mode == .shape ? _hand.outline : const <Offset>[];
    final swept = {..._swept};
    _hand.clear();
    _swept.clear();
    if (!keep) {
      if (swept.isNotEmpty) setState(() => _erased.removeAll(swept));
      return;
    }
    // Only what is seen goes into a group: a stroke out of sight, or erased and not
    // gone yet, was moved and deleted along with it unseen.
    final map = _withoutHidden(widget.state.map);
    switch (mode) {
      case .draw:
        widget.onDraw?.call(thinOut(points, _thinning / _camera.scale), null);
      case .shape:
        // A tap draws no shape: it would be a dot.
        final span = (points.last - points.first).distance * _camera.scale;
        if (span >= kTouchSlop) widget.onDraw?.call(outline, widget.penShape);
      case .erase:
        if (swept.isNotEmpty) widget.onErase?.call(swept);
      case .lasso:
        widget.onGroup?.call(insideLasso(map, points));
      case .rectangle:
        widget.onGroup?.call(
          insideRectangle(map, points.first, points.lastOrNull ?? points.first),
        );
    }
  }

  /// The strokes the eraser's last step went over: hidden at once, as the finger
  /// passes, and taken away together when it lifts.
  void _eraseAlong() {
    final points = _hand.points;
    final step = points.length < 2 ? points : points.sublist(points.length - 2);
    final hit = erasedBy(
      step,
      widget.state.map,
      _eraserReach / _camera.scale,
    ).difference(_erased);
    if (hit.isEmpty) return;
    setState(() {
      _erased.addAll(hit);
      _swept.addAll(hit);
    });
  }

  // --- The canvas itself: moved and zoomed ------------------------------------

  void _scaleStart(ScaleStartDetails details) {
    // By hand, one finger draws (above). The map moves with two, with the
    // trackpad, and with a finger left after a pinch.
    // Zooming with one finger, it does not move the map as well.
    _panning =
        _zooming == null &&
        (!_byHand ||
            details.pointerCount > 1 ||
            _several ||
            details.kind == .trackpad);
    if (_panning) _startMoving(details.localFocalPoint);
  }

  void _startMoving(Offset focal) {
    _startScale = _camera.scale;
    _startOrigin = _camera.origin;
    _startFocal = focal;
  }

  void _scaleUpdate(ScaleUpdateDetails details) {
    if (!_panning) {
      if (details.pointerCount < 2 || _zooming != null) return;
      _panning = true;
      _startMoving(details.localFocalPoint);
      return;
    }
    final scale = (_startScale * details.scale).clamp(
      MindmapCamera.minScale,
      MindmapCamera.maxScale,
    );
    // The point of the map under the fingers when they came down stays under them.
    final anchor = (_startFocal - _startOrigin) / _startScale;
    _camera.set(scale, details.localFocalPoint - anchor * scale);
  }

  void _scaleEnd(ScaleEndDetails _) => _panning = false;

  /// How far a stroke's points may stray from its line once thinned out, on screen.
  static const _thinning = 0.5;

  /// How far around the finger the eraser takes a stroke, on screen.
  static const _eraserReach = HiwiskiMetrics.mindmapEraser;

  /// An arrow's head drawn with the pen, by the pen's width.
  static const _headPerWidth = 4.0;

  /// How far a finger drags, tapped twice, for the map to zoom e-fold.
  static const _zoomDrag = 150.0;

  void _signal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent && event is! PointerScaleEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      switch (event) {
        // Two fingers pinched on a trackpad in the browser: the browser sends it as
        // a zoom of its own, not as two fingers moving.
        case PointerScaleEvent(:final localPosition, :final scale):
          _camera.zoomAt(localPosition, scale);
        case PointerScrollEvent(:final localPosition, :final scrollDelta):
          final keys = HardwareKeyboard.instance;
          // As in a drawing program: the wheel moves, with Ctrl or ⌘ it zooms.
          if (keys.isControlPressed || keys.isMetaPressed) {
            _camera.zoomAt(
              localPosition,
              math.pow(_wheelZoom, -scrollDelta.dy).toDouble(),
            );
          } else {
            _camera.panBy(-scrollDelta);
          }
      }
    });
  }

  void _tap(TapUpDetails details) {
    final at = _camera.toScene(details.localPosition);
    final map = widget.state.map;
    // A line is thin: a tap near it counts, as near on screen at every zoom.
    final reach = HiwiskiMetrics.minTapTarget / 2 / _camera.scale;
    for (final edge in map.edges.reversed) {
      final path = edgePathOf(map, edge, HiwiskiMetrics.mindmapEdgeSpread);
      if (path != null &&
          distanceToPath(at, path) <= reach + (edge.strokeWidth ?? 0) / 2) {
        widget.onSelect(.edge(edge.id));
        return;
      }
    }
    widget.onSelect(null);
  }

  // --- Elements: dragged, resized, connected ----------------------------------

  void _dragStart(MindmapNode node, DragStartDetails details) {
    // One of a group is dragged with the group, which stays selected.
    if (!widget.group.contains(node.id)) widget.onSelect(.node(node.id));
    _grab =
        _sceneAt(details.globalPosition) -
        Offset(node.x.toDouble(), node.y.toDouble());
  }

  /// What a drag moves: the element, or the whole group it belongs to.
  List<MindmapNode> _carried(MindmapNode node) => widget.group.contains(node.id)
      ? [for (final id in widget.group) ?widget.state.map.node(id)]
      : [node];

  void _dragUpdate(MindmapNode node, DragUpdateDetails details) {
    final grab = _grab;
    // A second tap on an element, dragged, zooms: the element stays.
    if (grab == null || _zooming != null) return;
    _followEdge(details.globalPosition);
    final at = _sceneAt(details.globalPosition) - grab;
    Offset by =
        Offset(at.dx.roundToDouble(), at.dy.roundToDouble()) -
        Offset(node.x.toDouble(), node.y.toDouble());
    final carried = _carried(node);
    MindmapGuides? guides;
    // Snapped while it moves, so what is seen is what is stored: the element, or
    // the box round the group, lines up with those around it.
    if (_snapping case (:final others, :final grid)) {
      final moving = carried
          .map((each) => each.turnedBounds)
          .reduce((a, b) => a.expandToInclude(b))
          .shift(by);
      final snapped = snapMove(
        moving,
        others(except: {for (final each in carried) each.id}),
        reach: HiwiskiMetrics.mindmapSnapReach / _camera.scale,
        grid: grid,
      );
      by += Offset(
        snapped.by.dx.roundToDouble(),
        snapped.by.dy.roundToDouble(),
      );
      guides = (lines: snapped.guides, gaps: snapped.gaps, matched: const []);
    }
    setState(() {
      _guides = guides;
      for (final each in carried) {
        _moving[each.id] = each.moved(by);
      }
    });
  }

  /// What a moved or resized element snaps to now — the boxes of the others but
  /// those [except]ed, and the grid's spacing — or `null` while it snaps to
  /// nothing: both switched off, or ⌘ or Ctrl held to place it freely.
  ({List<Rect> Function({required Set<String> except}) others, double? grid})?
  get _snapping {
    final keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed || keys.isControlPressed) return null;
    // Snapping off is off for the grid too: it is then only seen, a help for the
    // eye.
    if (!widget.snap) return null;
    final near = _camera.nearby;
    return (
      others: ({required Set<String> except}) => [
        for (final other in widget.state.map.nodes)
          // A stroke drawn freehand is no line to meet; a shape drawn is.
          if (!except.contains(other.id) &&
              !(other.kind == MindmapKinds.drawing && other.penShape == null) &&
              near.overlaps(other.turnedBounds))
            other.turnedBounds,
      ],
      grid: widget.grid ? HiwiskiMetrics.mindmapGrid : null,
    );
  }

  void _dragEnd(MindmapNode node) {
    final moves = <MindmapNode, ({int x, int y})>{};
    setState(() {
      _guides = null;
      for (final each in _carried(node)) {
        final to = _moving.remove(each.id);
        if (to != null && (to.x != each.x || to.y != each.y)) {
          _settle(each, to);
          moves[each] = (x: to.x, y: to.y);
        }
      }
      _grab = null;
    });
    if (moves.isNotEmpty) widget.onMove(moves);
  }

  /// Near the canvas's edge a drag moves the view along, so an element can be taken
  /// beyond what is shown.
  void _followEdge(Offset global) {
    final box = _area.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    final local = box.globalToLocal(global);
    final size = box.size;
    final push = Offset(
      _push(local.dx, size.width),
      _push(local.dy, size.height),
    );
    if (push != .zero) _camera.panBy(push);
  }

  /// The point of the map where a resize took the corner.
  Offset? _resizeFrom;

  void _resizeStart(DragStartDetails details) {
    _resizeFrom = _sceneAt(details.globalPosition);
  }

  /// The corner follows the pointer exactly: the size is the element's when the
  /// drag began and how far the pointer has gone on the map since. Added up from each
  /// frame's step, the step came already in the map's units and was divided by the
  /// zoom once more — zoomed out, the element grew several times as fast as the
  /// finger went.
  void _resizeUpdate(MindmapNode node, DragUpdateDetails details) {
    final at = _sceneAt(details.globalPosition);
    // In the element's own frame: turned, its corner goes along its own edges.
    final moved = turnOffset(at - (_resizeFrom ??= at), -node.turn);
    Size to = Size(
      math.max(HiwiskiMetrics.mindmapMinElement, node.width + moved.dx),
      math.max(HiwiskiMetrics.mindmapMinElement, node.height + moved.dy),
    );
    // A picture keeps its shape: it fills its element whole, never cut and never
    // with a margin — and a member's circle stays round. The way the pointer went
    // further decides the size.
    if (node.keepsShape) {
      final aspect = node.width / node.height;
      to = to.width / aspect >= to.height
          ? Size(to.width, to.width / aspect)
          : Size(to.height * aspect, to.height);
    }
    MindmapGuides? guides;
    // Turned, its edges run across the map's lines: it is resized freely.
    if (_snapping case (:final others, :final grid) when node.turn == 0) {
      final snapped = snapResize(
        Rect.fromLTWH(
          node.x.toDouble(),
          node.y.toDouble(),
          to.width,
          to.height,
        ),
        others(except: {node.id}),
        reach: HiwiskiMetrics.mindmapSnapReach / _camera.scale,
        grid: grid,
        aspect: node.keepsShape ? node.width / node.height : null,
        minimum: HiwiskiMetrics.mindmapMinElement,
      );
      to = snapped.size;
      guides = (
        lines: snapped.guides,
        gaps: const [],
        matched: snapped.matched,
      );
    }
    setState(() {
      _guides = guides;
      _moving[node.id] = node.resizedTo(to.width.round(), to.height.round());
    });
  }

  /// Turning by the knob: the angle from the element's centre to the pointer, the
  /// knob standing above it — held at each fifteenth degree within a few, so that a
  /// right angle is easy to meet and any other still possible.
  void _rotateUpdate(MindmapNode node, DragUpdateDetails details) {
    final towards = _sceneAt(details.globalPosition) - node.center;
    final degrees =
        (math.atan2(towards.dy, towards.dx) + math.pi / 2) * _degreesPerRadian;
    final step = (degrees / _rotateSnap).round() * _rotateSnap;
    final snapped = (degrees - step).abs() <= _rotateSnapWithin
        ? step
        : degrees;
    setState(() {
      _moving[node.id] = node.styled(rotation: Change(rotationOf(snapped)));
    });
  }

  void _rotateEnd(MindmapNode node) {
    MindmapNode? turned;
    setState(() => turned = _moving.remove(node.id));
    final to = turned;
    if (to != null && to.rotation != node.rotation) {
      _settle(node, to);
      widget.onRotate(node, to.rotation);
    }
  }

  static const _degreesPerRadian = 180 / math.pi;
  static const _rotateSnap = 15.0;
  static const _rotateSnapWithin = 4.0;

  /// How far the view moves for a pointer at [at] of [extent]: towards the edge it is
  /// near, if it is near one.
  static double _push(double at, double extent) => switch (at) {
    < HiwiskiMetrics.dragAutoScrollEdge => HiwiskiMetrics.kanbanEdgeScrollStep,
    _ when at > extent - HiwiskiMetrics.dragAutoScrollEdge =>
      -HiwiskiMetrics.kanbanEdgeScrollStep,
    _ => 0,
  };

  void _resizeEnd(MindmapNode node) {
    MindmapNode? resized;
    _resizeFrom = null;
    setState(() {
      _guides = null;
      resized = _moving.remove(node.id);
    });
    final size = resized;
    if (size != null &&
        (size.width != node.width || size.height != node.height)) {
      _settle(node, size);
      widget.onResize(node, (width: size.width, height: size.height));
    }
  }

  /// Whether the map is bare under the finger at [global]: no element there, nor
  /// the grips of the one selected. Only there do two taps and a drag zoom — an
  /// element tapped and then its knob taken at once zoomed the map instead of
  /// turning it.
  bool _emptyAt(Offset global) {
    final at = _sceneAt(global);
    final finger = HiwiskiMetrics.minTapTarget / _camera.scale;
    final selected = widget.state.map.node(widget.selection?.id ?? '');
    final grips =
        selected?.turnedBounds.inflate(
          finger + HiwiskiMetrics.mindmapRotateReach / _camera.scale,
        ) ??
        .zero;
    // A stroke only near its line, as it takes a finger: the box around a stroke
    // across the map is mostly bare canvas.
    return _nodeAt(at) == null &&
        !widget.state.map.nodes.any(
          (node) =>
              !_hidden(node) &&
              (node.kind == MindmapKinds.drawing
                  ? nearStroke(node, at, finger / 2)
                  : node.turnedBounds.inflate(finger / 2).contains(at)),
        ) &&
        !grips.contains(at);
  }

  /// Whether [node] is out of sight: taken by the eraser and not gone from the map
  /// yet, or a stroke while they are hidden.
  bool _hidden(MindmapNode node) =>
      _erased.contains(node.id) ||
      (widget.hideDrawings && node.kind == MindmapKinds.drawing);

  /// [map] as it is seen ([_hidden]).
  Mindmap _withoutHidden(Mindmap map) => _erased.isEmpty && !widget.hideDrawings
      ? map
      : .new(
          nodes: [
            for (final node in map.nodes)
              if (!_hidden(node)) node,
          ],
          edges: map.edges,
        );

  /// The topmost element seen at [at], a point of the map — a stroke only near its
  /// line, where it takes a tap too: by its box, a stroke drawn over an element took
  /// the connection meant for the element.
  MindmapNode? _nodeAt(Offset at, {String? except}) {
    for (final node in widget.state.map.nodes.reversed) {
      if (node.id == except || _hidden(node)) continue;
      final hit = node.kind == MindmapKinds.drawing
          ? nearStroke(node, at, _strokeReach)
          : node.covers(at);
      if (hit) return node;
    }
    return null;
  }

  /// How far from its line a stroke takes a finger, in the map's units — as far as
  /// its element takes a tap ([StrokePainter]).
  double get _strokeReach => HiwiskiMetrics.minTapTarget / 4 / _camera.scale;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _camera,
    builder: (context, _) {
      final state = widget.state;
      final editing = widget.editing && state.writable;
      // What is written, or being written, but not in the map yet.
      Mindmap shown = state.map;
      for (final extra in [...widget.held, ?widget.writing?.node]) {
        shown = shown.node(extra.id) == null
            ? shown.plus(extra)
            : shown.withNodes({extra.id: extra});
      }
      shown = _withoutHidden(shown);
      final writing = widget.writing;
      final map = shown.withNodes({
        // Only while the element is as it was: once it changed in the map, the map
        // shows it.
        for (final MapEntry(key: id, value: (:from, :to)) in _settling.entries)
          if (state.map.node(id) == from) id: to,
        ..._moving,
      });
      final scale = _camera.scale;
      final area = MindmapScene.areaOf(map, zoom: scale);
      final selection = widget.selection;
      final drawing = _drawing;
      final target = drawing == null
          ? null
          : _nodeAt(drawing.$2, except: drawing.$1.id);
      return Semantics(
        label: L.of(context).mindmapCanvas,
        child: Listener(
          onPointerSignal: _signal,
          onPointerHover: _hover,
          onPointerDown: _fingerDown,
          onPointerMove: _fingerMove,
          onPointerUp: _fingerUp,
          onPointerCancel: _fingerUp,
          child: DragTarget<String>(
            onAcceptWithDetails: (details) =>
                widget.onDrop(details.data, _sceneAt(details.offset)),
            builder: (context, _, _) => LayoutBuilder(
              builder: (context, constraints) {
                _camera.resize(constraints.biggest);
                if (!_camera.placed) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_camera.placed) widget.onReady();
                  });
                }
                return ClipRect(
                  child: GestureDetector(
                    key: _area,
                    behavior: .opaque,
                    excludeFromSemantics: true,
                    onTapUp: _byHand ? null : _tap,
                    onScaleStart: _scaleStart,
                    onScaleUpdate: _scaleUpdate,
                    onScaleEnd: _scaleEnd,
                    child: Stack(
                      clipBehavior: .none,
                      children: [
                        if (widget.grid)
                          Positioned.fill(child: MindmapGrid(camera: _camera)),
                        Positioned(
                          left: _camera.origin.dx + area.left * scale,
                          top: _camera.origin.dy + area.top * scale,
                          child: Transform.scale(
                            scale: scale,
                            alignment: .topLeft,
                            child: MindmapScene(
                              map: map,
                              area: area,
                              visible: _camera.nearby,
                              zoom: scale,
                              linkTarget: state.targetOf,
                              // Read, what is on an element is used — pictures
                              // turned, a chip followed; edited, a drag moves it.
                              interactive: !editing,
                              selected: {
                                ?selection?.id,
                                ?target?.id,
                                ...widget.group,
                                ?_linkFrom,
                              },
                              found: widget.found,
                              conflicts: state.conflicts.keys.toSet(),
                              mine: widget.mine,
                              labels: widget.labels,
                              hand: _hand,
                              guides: _guides,
                              pendingLine: drawing == null
                                  ? null
                                  : (drawing.$1.center, drawing.$2),
                              pendingStyle: widget.linkStyle,
                              pendingLook: widget.linkLook,
                              writing: writing == null
                                  ? null
                                  : (id: writing.node.id, field: writing.field),
                              // Written in, an element is not moved: a drag on it
                              // selects words.
                              // Drawing or erasing, a finger acts on the canvas,
                              // not on the element under it.
                              element: (node, child) =>
                                  node.id == writing?.node.id || _byHand
                                  ? child
                                  : _Element(
                                      editing: editing,
                                      precise:
                                          node.kind == MindmapKinds.drawing,
                                      onTap: () {
                                        if (!editing) {
                                          widget.onOpen(node);
                                        } else if (selection ==
                                            MindmapSelection.node(node.id)) {
                                          widget.onOpen(node);
                                        } else {
                                          widget.onSelect(.node(node.id));
                                        }
                                      },
                                      onDragStart: (details) => _dragStart(
                                        state.map.node(node.id) ?? node,
                                        details,
                                      ),
                                      onDragUpdate: (details) => _dragUpdate(
                                        state.map.node(node.id) ?? node,
                                        details,
                                      ),
                                      onDragEnd: () => _dragEnd(
                                        state.map.node(node.id) ?? node,
                                      ),
                                      child: child,
                                    ),
                              // Not while it is written: its size follows the text.
                              // A stroke is not resized: drawn again, if need be.
                              // A stroke drawn freehand is not resized: drawn
                              // again, if need be. One drawn as a shape is.
                              resizable:
                                  editing &&
                                      !_byHand &&
                                      switch (map.node(selection?.id ?? '')) {
                                        final node? =>
                                          node.kind != MindmapKinds.drawing ||
                                              node.penShape != null,
                                        null => false,
                                      } &&
                                      selection?.edge == false &&
                                      selection?.id != writing?.node.id
                                  ? selection?.id
                                  : null,
                              // Every element turns — not while written in.
                              rotatable:
                                  editing &&
                                      !_byHand &&
                                      selection?.edge == false &&
                                      selection?.id != writing?.node.id
                                  ? selection?.id
                                  : null,
                              rotate: (node, knob) => GestureDetector(
                                behavior: .opaque,
                                excludeFromSemantics: true,
                                supportedDevices: _pointing,
                                dragStartBehavior: .down,
                                onPanUpdate: (details) => _rotateUpdate(
                                  state.map.node(node.id) ?? node,
                                  details,
                                ),
                                onPanEnd: (_) =>
                                    _rotateEnd(state.map.node(node.id) ?? node),
                                onPanCancel: () =>
                                    _rotateEnd(state.map.node(node.id) ?? node),
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.grab,
                                  child: knob,
                                ),
                              ),
                              resize: (node, corner) => GestureDetector(
                                behavior: .opaque,
                                excludeFromSemantics: true,
                                supportedDevices: _pointing,
                                // From where the finger came down: begun where the
                                // drag was recognised, the corner lagged behind it.
                                dragStartBehavior: .down,
                                onPanStart: _resizeStart,
                                onPanUpdate: (details) => _resizeUpdate(
                                  state.map.node(node.id) ?? node,
                                  details,
                                ),
                                onPanEnd: (_) =>
                                    _resizeEnd(state.map.node(node.id) ?? node),
                                onPanCancel: () =>
                                    _resizeEnd(state.map.node(node.id) ?? node),
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.resizeDownRight,
                                  child: corner,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    },
  );

  static const _wheelZoom = 1.002;

  /// What drags an element: a finger, a mouse, a pen — not two fingers on a
  /// trackpad, which move the canvas.
  static const _pointing = {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };
}

/// An element with the gestures of the canvas: a tap opens or selects it; while
/// editing it is dragged. Its grips — the connection dot, the selected one's resize
/// corner — are the scene's, mostly outside it.
class _Element extends StatelessWidget {
  const _Element({
    required this.editing,
    required this.precise,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.child,
  });

  final bool editing;

  /// Taken only where its content takes a hit — a stroke near its line — not across
  /// its whole box.
  final bool precise;
  final VoidCallback onTap;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final VoidCallback onDragEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!editing) {
      return GestureDetector(
        excludeFromSemantics: true,
        onTap: onTap,
        child: child,
      );
    }
    return GestureDetector(
      excludeFromSemantics: true,
      supportedDevices: _MindmapCanvasState._pointing,
      // Held where the finger came down: taken where the drag was recognised, the
      // element lagged behind the finger by that much.
      dragStartBehavior: .down,
      onTap: onTap,
      onPanStart: onDragStart,
      onPanUpdate: onDragUpdate,
      onPanEnd: (_) => onDragEnd(),
      onPanCancel: onDragEnd,
      // Precise: hit where the child is — the stroke's line — and only there. Not
      // by `opaque: false`: a region that lets hits through tells the gestures
      // around it that nothing was hit, and a stroke could not be selected.
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        hitTestBehavior: precise ? .deferToChild : null,
        child: child,
      ),
    );
  }
}
