import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/common/wire.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/theme/mindmap_colors.dart';
import '../../../../domain/wiki/mindmap.dart';
import '../../../../domain/wiki/mindmap_snap.dart';
import 'mindmap_element.dart';
import 'mindmap_lines.dart';

export 'mindmap_element.dart';
export 'mindmap_lines.dart';

/// A mind map drawn in its own units — elements, connections, labels — for the
/// page's preview and for the canvas, which scales and moves it.
///
/// It draws; it does not decide. What is selected, found or in conflict, where a
/// gesture has an element right now, and what a tap does come from the screen
/// around it: [element] wraps each element in the screen's gestures, [resize] the
/// selected one's corner.
class MindmapScene extends StatelessWidget {
  const MindmapScene({
    super.key,
    required this.map,
    required this.area,
    required this.linkTarget,
    this.interactive = false,
    this.visible,
    this.zoom = 1,
    this.selected = const {},
    this.found = const {},
    this.conflicts = const {},
    this.pendingLine,
    this.pendingStyle,
    this.pendingLook,
    this.mine,
    this.labels,
    this.element,
    this.resizable,
    this.resize,
    this.rotatable,
    this.rotate,
    this.writing,
    this.hand,
    this.guides,
  });

  final Mindmap map;

  /// The part of the canvas the scene covers, in the map's units: the map's bounds
  /// and a margin ([areaOf]).
  final Rect area;

  final MindmapLinkTarget linkTarget;

  /// Whether the elements' content takes taps and swipes ([MindmapElementView]).
  final bool interactive;

  /// The part to build, in the map's units — the canvas passes what is in view and a
  /// screen's worth around it. `null`: everything (the preview).
  final Rect? visible;

  /// The scale the scene is shown at — handles and frames keep their size on screen.
  final double zoom;

  /// Elements and connections selected for editing.
  final Set<String> selected;

  /// What a search found: drawn above everything, the rest faded.
  final Set<String> found;

  /// Elements and connections whose change lost against someone else's.
  final Set<String> conflicts;

  /// A connection being drawn: from an element's centre to the pointer — in the
  /// way it will be drawn, where given.
  final (Offset, Offset)? pendingLine;
  final MindmapEdgeStyle? pendingStyle;
  final ({String? color, int? width})? pendingLook;

  /// An element in conflict as this device wrote it — drawn faintly and dashed
  /// beside the map's version, the two named by [labels]: what was decided between
  /// them is seen, not read.
  final MindmapNode? mine;

  /// What [mine] and the map's version are called: this device's, the server's.
  final ({String mine, String theirs})? labels;

  /// Wraps an element in the screen's gestures.
  final Widget Function(MindmapNode node, Widget child)? element;

  /// The element with a corner to resize it by — the selected one, while editing.
  final String? resizable;

  /// Wraps that corner in the screen's gestures.
  final Widget Function(MindmapNode node, Widget corner)? resize;

  /// The element with a knob above it to turn it by — the selected one, while
  /// editing — and that knob wrapped in the screen's gestures.
  final String? rotatable;
  final Widget Function(MindmapNode node, Widget knob)? rotate;

  /// The element being written on the canvas, and the field it is written in.
  final ({String id, Widget field})? writing;

  /// What a hand draws or erases right now, painted over everything.
  final MindmapHand? hand;

  /// What the element being moved or resized lines up with: the guides, the equal
  /// gaps, the elements whose size it took — painted over the map.
  final MindmapGuides? guides;

  /// The area a scene of [map] covers at [zoom]: the map's bounds and a margin, wide
  /// enough for the grips on the outermost elements to take a finger.
  static Rect areaOf(Mindmap map, {double zoom = 1}) =>
      (map.bounds ?? .zero).inflate(
        math.max(
          HiwiskiMetrics.mindmapSceneMargin,
          (HiwiskiMetrics.minTapTarget + HiwiskiMetrics.mindmapFrameGap) / zoom,
        ),
      );

  /// How far a small element takes a finger beyond its edges: to a finger's width
  /// on screen ([grip], in the map's units), at every zoom — a short snippet was hard
  /// to take and move. Only where the screen's gestures wrap it, and not for a
  /// stroke, which is taken on its line alone.
  static EdgeInsets _reachOf(
    MindmapNode node,
    Widget Function(MindmapNode, Widget)? wrap,
    double grip,
  ) => wrap == null || node.kind == MindmapKinds.drawing
      ? .zero
      : .symmetric(
          horizontal: math.max(0, (grip - node.width) / 2),
          vertical: math.max(0, (grip - node.height) / 2),
        );

  /// What the connections are drawn within: [visible] grown outwards to a grid of
  /// about a screen's size. The connections lie on a layer of their own that a move
  /// of the map does not redraw; drawn within [visible] itself, they would be redrawn
  /// in every frame of it, but this way only as it crosses a line of the grid — and
  /// what is seen always lies within what was drawn.
  static Rect _cullOf(Rect visible) {
    final cell = visible.longestSide / _cullCells;
    if (cell <= 0) return visible;
    double down(double value) => (value / cell).floorToDouble() * cell;
    double up(double value) => (value / cell).ceilToDouble() * cell;
    return .fromLTRB(
      down(visible.left),
      down(visible.top),
      up(visible.right),
      up(visible.bottom),
    );
  }

  /// [visible] is the view and a screen's worth around it: three screens across.
  static const _cullCells = 3;

  /// How far a grip reaches into its element at most, as a share of the element:
  /// the rest of it is moved by a drag, at every zoom.
  static const _gripReach = 1 / 3;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final searching = found.isNotEmpty;
    final inView = visible;
    final shown = [
      for (final node in map.nodes)
        if (inView == null ||
            inView.overlaps(
              node.bounds.inflate(HiwiskiMetrics.mindmapSceneMargin),
            ))
          node,
    ];
    final wrap = element;
    // What was found lies above the rest while the search is open — its stored
    // layer stays.
    final ordered = searching
        ? [
            for (final node in shown)
              if (!found.contains(node.id)) node,
            for (final node in shown)
              if (found.contains(node.id)) node,
          ]
        : shown;
    // The resize corner is as large to a finger at every zoom, but lies mostly
    // outside its element: of a fixed size and inside
    // it, zoomed far out it covered the whole element, and a drag meant to move it
    // drew a connection or resized it instead.
    final grip = HiwiskiMetrics.minTapTarget / zoom;
    final dot = HiwiskiMetrics.mindmapHandle / zoom;
    final gap = HiwiskiMetrics.mindmapFrameGap / zoom;
    final sized = switch (resizable) {
      final String id => map.node(id),
      null => null,
    };
    final reach = sized == null
        ? 0.0
        : math.min(grip / 2, math.min(sized.width, sized.height) * _gripReach);
    final ghost = mine;
    final theirs = ghost == null ? null : map.node(ghost.id);
    final named = labels;
    final ghostBounds = ghost == null || theirs == null
        ? null
        : mineBoundsOf(theirs, ghost, HiwiskiMetrics.mindmapConflictGap);
    // Drawn in the map's own units and zoomed by hand: text the system would scale
    // too would not fit the elements another device measured.
    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        width: area.width,
        height: area.height,
        child: Stack(
          clipBehavior: .none,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _EdgesPainter(
                    map: map,
                    origin: area.topLeft,
                    paints: {
                      for (final edge in map.edges)
                        edge.id: MindmapPaint.of(context, edge.color),
                    },
                    label: context.texts.bodySmall ?? const TextStyle(),
                    labelInk: scheme.onSurface,
                    background: scheme.surface,
                    accent: scheme.primary,
                    highlight: context.tokens.highlight.background,
                    selected: selected,
                    found: found,
                    conflicts: conflicts,
                    conflictInk: scheme.tertiary,
                    pendingLine: pendingLine,
                    pendingStyle: pendingStyle,
                    // In the colour and thickness it will have, where chosen.
                    pendingInk: switch (pendingLook?.color) {
                      final String color => MindmapPaint.of(
                        context,
                        color,
                      ).line,
                      null => scheme.primary,
                    },
                    pendingWidth: pendingLook?.width?.toDouble(),
                    zoom: zoom,
                    cull: switch (visible) {
                      final visible? => _cullOf(visible),
                      null => null,
                    },
                  ),
                ),
              ),
            ),
            for (final node in ordered) ...[
              Positioned(
                key: ValueKey(node.id),
                left:
                    node.x -
                    area.left -
                    _reachOf(node, wrap, grip).horizontal / 2,
                top:
                    node.y - area.top - _reachOf(node, wrap, grip).vertical / 2,
                width: node.width + _reachOf(node, wrap, grip).horizontal,
                height: node.height + _reachOf(node, wrap, grip).vertical,
                // Turned about its centre, and taken where it is seen: a
                // transform's hits follow it.
                child: Transform.rotate(
                  angle: node.turn,
                  child: Opacity(
                    // What a search did not find fades back.
                    opacity: searching && !found.contains(node.id)
                        ? _fadedOpacity
                        : 1,
                    child: MindmapElementView(
                      node: node,
                      linkTarget: linkTarget,
                      interactive: interactive,
                      zoom: zoom,
                      selected: selected.contains(node.id),
                      found: found.contains(node.id),
                      conflict: conflicts.contains(node.id),
                      wrap: wrap,
                      reach: _reachOf(node, wrap, grip),
                      editor: writing?.id == node.id ? writing?.field : null,
                    ),
                  ),
                ),
              ),
            ],
            if ((
                  switch (rotatable) {
                    final String id => map.node(id),
                    null => null,
                  },
                  rotate,
                )
                case (final node?, final wrap?))
              _TurnedWith(
                node: node,
                area: area,
                child: _Grip(
                  key: ValueKey('${node.id}$_rotateSuffix'),
                  // Above the middle of its top edge, clear of the frame.
                  at: Offset(
                    node.x + node.width / 2 - area.left,
                    node.y -
                        gap -
                        HiwiskiMetrics.mindmapRotateReach / zoom -
                        area.top,
                  ),
                  inward: Offset(grip / 2, grip / 2),
                  size: grip,
                  dot: dot * _knobPerDot,
                  wrap: (child) => wrap(node, child),
                  mark: ShapeDecoration(
                    shape: CircleBorder(
                      side: BorderSide(
                        color: scheme.primary,
                        width: HiwiskiMetrics.strokeBold / zoom,
                      ),
                    ),
                    color: scheme.surface,
                  ),
                ),
              ),
            if ((sized, resize) case (final node?, final wrap?))
              _TurnedWith(
                node: node,
                area: area,
                child: _Grip(
                  key: ValueKey('${node.id}$_resizeSuffix'),
                  // On the corner of the frame, which stands a little off the
                  // element.
                  at: Offset(
                    node.x + node.width + gap - area.left,
                    node.y + node.height + gap - area.top,
                  ),
                  inward: Offset(reach, reach),
                  size: grip,
                  dot: dot,
                  wrap: (child) => wrap(node, child),
                  mark: BoxDecoration(
                    color: scheme.surface,
                    border: .fromBorderSide(
                      BorderSide(
                        color: scheme.primary,
                        width: HiwiskiMetrics.strokeBold / zoom,
                      ),
                    ),
                  ),
                ),
              ),
            if (hand case final hand?)
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _HandPainter(
                        hand: hand,
                        origin: area.topLeft,
                        eraserColor: scheme.outline,
                        selectColor: scheme.primary,
                        zoom: zoom,
                      ),
                    ),
                  ),
                ),
              ),
            if (guides case final guides?)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _GuidesPainter(
                      guides: guides,
                      origin: area.topLeft,
                      // Not the selection's colour: what lines up is not what is
                      // selected.
                      color: context.tokens.accent(.pink),
                      zoom: zoom,
                    ),
                  ),
                ),
              ),
            if (ghost != null && theirs != null && ghostBounds != null) ...[
              Positioned(
                key: const ValueKey(_mineKey),
                left: ghostBounds.left - area.left,
                top: ghostBounds.top - area.top,
                width: ghostBounds.width,
                height: ghostBounds.height,
                child: IgnorePointer(
                  child: Stack(
                    fit: .expand,
                    children: [
                      Opacity(
                        opacity: _mineOpacity,
                        // A copy of the element: its pictures must not fly into
                        // a large view as the element's own do.
                        child: HeroMode(
                          enabled: false,
                          child: MindmapElementView(
                            node: ghost,
                            linkTarget: linkTarget,
                            zoom: zoom,
                          ),
                        ),
                      ),
                      CustomPaint(
                        painter: _DashedOutline(
                          color: scheme.tertiary,
                          width: HiwiskiMetrics.strokeBold / zoom,
                          dash: HiwiskiMetrics.space6 / zoom,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (named != null) ...[
                _Label(
                  at: ghostBounds.topLeft - area.topLeft,
                  zoom: zoom,
                  text: named.mine,
                  strong: true,
                ),
                _Label(
                  at: theirs.bounds.topLeft - area.topLeft,
                  zoom: zoom,
                  text: named.theirs,
                  strong: false,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static const _fadedOpacity = 0.3;
  static const _mineOpacity = 0.6;
  static const _resizeSuffix = '-resize';
  static const _rotateSuffix = '-rotate';

  /// The knob to turn by is a little larger than the resize corner.
  static const _knobPerDot = 1.4;
  static const _mineKey = 'mindmap-mine';
}

/// What a hand is doing on the canvas right now — a stroke being drawn, or the eraser
/// swiped — in the map's units. It changes with every move of the finger and
/// repaints its own layer, nothing else.
class MindmapHand extends ChangeNotifier {
  final _points = <Offset>[];
  bool _active = false;
  MindmapHandMode _mode = .draw;
  Color _color = Colors.transparent;
  double _width = 1;
  double _radius = 0;
  MindmapPenShape _shape = .rectangle;
  double _head = 0;

  /// Whether a stroke is being drawn or the eraser swiped.
  bool get active => _active;

  /// What the hand does.
  MindmapHandMode get mode => _mode;

  /// A stroke — rather than the eraser or a selection.
  bool get drawing => _mode == .draw;

  /// Where it has gone so far.
  List<Offset> get points => UnmodifiableListView(_points);

  Offset get last => _points.lastOrNull ?? .zero;

  /// Begins a stroke at [at], [width] thick in the map's units.
  void draw(Offset at, {required Color color, required double width}) {
    _begin(at, .draw);
    _color = color;
    _width = width;
    notifyListeners();
  }

  /// Begins a swipe of the eraser at [at], taking strokes within [radius].
  void erase(Offset at, {required double radius}) {
    _begin(at, .erase);
    _radius = radius;
    notifyListeners();
  }

  /// Begins [shape] at [at], drawn to where the finger goes, [width] thick in the
  /// map's units; an arrow's head is [head] long.
  void shape(
    Offset at,
    MindmapPenShape shape, {
    required Color color,
    required double width,
    required double head,
  }) {
    _begin(at, .shape);
    _shape = shape;
    _color = color;
    _width = width;
    _head = head;
    notifyListeners();
  }

  /// The outline of the shape drawn so far.
  List<Offset> get outline =>
      penShapeOutline(_shape, _points.firstOrNull ?? .zero, last, head: _head);

  /// Begins a selection at [at]: a lasso, or a rectangle to where the finger goes.
  void select(Offset at, {required bool rectangle}) {
    _begin(at, rectangle ? .rectangle : .lasso);
    notifyListeners();
  }

  void _begin(Offset at, MindmapHandMode mode) {
    _points
      ..clear()
      ..add(at);
    _active = true;
    _mode = mode;
  }

  void add(Offset at) {
    _points.add(at);
    notifyListeners();
  }

  void clear() {
    _points.clear();
    _active = false;
    notifyListeners();
  }
}

/// What a hand does on the canvas.
enum MindmapHandMode { draw, erase, lasso, rectangle, shape }

/// What an element being moved or resized lines up with: the guide lines, the equal
/// gaps of its row, the elements whose width or height it took.
typedef MindmapGuides = ({
  List<SnapGuide> lines,
  List<SnapGap> gaps,
  List<Rect> matched,
});

/// Paints [MindmapGuides]: thin lines, the equal gaps with a mark at each end, and a
/// frame round each element whose size was taken — all as thin on screen at every
/// zoom.
class _GuidesPainter extends CustomPainter {
  _GuidesPainter({
    required this.guides,
    required this.origin,
    required this.color,
    required this.zoom,
  });

  final MindmapGuides guides;
  final Offset origin;
  final Color color;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(-origin.dx, -origin.dy);
    final line = Paint()
      ..color = color
      ..style = .stroke
      ..strokeWidth = HiwiskiMetrics.hairline * 2 / zoom;
    for (final guide in guides.lines) {
      canvas.drawLine(
        guide.vertical
            ? Offset(guide.at, guide.from)
            : Offset(guide.from, guide.at),
        guide.vertical
            ? Offset(guide.at, guide.to)
            : Offset(guide.to, guide.at),
        line,
      );
    }
    final tick = HiwiskiMetrics.mindmapGapTick / zoom;
    for (final gap in guides.gaps) {
      final (start, end) = gap.horizontal
          ? (Offset(gap.from, gap.across), Offset(gap.to, gap.across))
          : (Offset(gap.across, gap.from), Offset(gap.across, gap.to));
      final side = gap.horizontal ? Offset(0, tick) : Offset(tick, 0);
      canvas
        ..drawLine(start, end, line)
        ..drawLine(start - side, start + side, line)
        ..drawLine(end - side, end + side, line);
    }
    for (final box in guides.matched) {
      canvas.drawRect(box, line);
    }
  }

  @override
  bool shouldRepaint(_GuidesPainter old) =>
      old.guides != guides ||
      old.origin != origin ||
      old.color != color ||
      old.zoom != zoom;
}

/// Paints [MindmapHand]: the stroke as it goes, the eraser where the finger is, the
/// lasso or the rectangle a selection is made with.
class _HandPainter extends CustomPainter {
  _HandPainter({
    required this.hand,
    required this.origin,
    required this.eraserColor,
    required this.selectColor,
    required this.zoom,
  }) : super(repaint: hand);

  final MindmapHand hand;
  final Offset origin;
  final Color eraserColor;
  final Color selectColor;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    if (!hand.active) return;
    canvas.translate(-origin.dx, -origin.dy);
    final outline = Paint()
      ..color = selectColor
      ..style = .stroke
      ..strokeWidth = HiwiskiMetrics.strokeBold / zoom;
    final fill = Paint()..color = selectColor.withValues(alpha: _selectFill);
    switch (hand.mode) {
      case .draw:
        paintStroke(canvas, hand.points, hand._color, hand._width);
      case .shape:
        paintStroke(canvas, hand.outline, hand._color, hand._width);
      case .erase:
        canvas.drawCircle(
          hand.last,
          hand._radius,
          Paint()
            ..color = eraserColor
            ..style = .stroke
            ..strokeWidth = HiwiskiMetrics.hairline / zoom,
        );
      case .lasso:
        final points = hand.points;
        final path = Path()..addPolygon(points, true);
        canvas
          ..drawPath(path, fill)
          ..drawPath(path, outline);
      case .rectangle:
        final area = Rect.fromPoints(hand.points.first, hand.last);
        canvas
          ..drawRect(area, fill)
          ..drawRect(area, outline);
    }
  }

  /// How much of the selection's colour fills what it goes round.
  static const _selectFill = 0.12;

  @override
  bool shouldRepaint(_HandPainter old) =>
      old.hand != hand ||
      old.origin != origin ||
      old.eraserColor != eraserColor ||
      old.selectColor != selectColor ||
      old.zoom != zoom;
}

/// [child] — a grip laid out on the whole scene, as if [node] were not turned — turned
/// with [node] about its centre, so that it stays on the element as it is seen.
class _TurnedWith extends StatelessWidget {
  const _TurnedWith({
    required this.node,
    required this.area,
    required this.child,
  });

  final MindmapNode node;
  final Rect area;
  final Widget child;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: Transform.rotate(
      angle: node.turn,
      alignment: .topLeft,
      origin: node.center - area.topLeft,
      child: Stack(clipBehavior: .none, children: [child]),
    ),
  );
}

/// A grip on an element's outline: a target of [size] around the point [at], of which
/// only [inward] — across and down — lies towards the element, with its [mark] on
/// [at].
class _Grip extends StatelessWidget {
  const _Grip({
    super.key,
    required this.at,
    required this.inward,
    required this.size,
    required this.dot,
    required this.wrap,
    required this.mark,
  });

  final Offset at;
  final Offset inward;
  final double size;
  final double dot;
  final Widget Function(Widget child) wrap;
  final Decoration mark;

  @override
  Widget build(BuildContext context) => Positioned(
    left: at.dx - inward.dx,
    top: at.dy - inward.dy,
    width: size,
    height: size,
    child: wrap(
      Stack(
        clipBehavior: .none,
        children: [
          Positioned(
            left: inward.dx - dot / 2,
            top: inward.dy - dot / 2,
            width: dot,
            height: dot,
            child: DecoratedBox(decoration: mark),
          ),
        ],
      ),
    ),
  );
}

/// A name over an element's top left corner, as large on screen at every zoom.
class _Label extends StatelessWidget {
  const _Label({
    required this.at,
    required this.zoom,
    required this.text,
    required this.strong,
  });

  final Offset at;
  final double zoom;
  final String text;

  /// This device's version: in the conflict's colour; the other plainly.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: at.dx,
      top: at.dy - HiwiskiMetrics.space4 / zoom,
      child: FractionalTranslation(
        // Above the corner, not over the element.
        translation: const Offset(0, -1),
        child: Transform.scale(
          scale: 1 / zoom,
          alignment: .bottomLeft,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              color: strong ? scheme.tertiary : scheme.surfaceContainerHighest,
            ),
            child: Padding(
              padding: const .symmetric(
                horizontal: HiwiskiMetrics.space8,
                vertical: HiwiskiMetrics.space2,
              ),
              child: Text(
                text,
                style: context.texts.labelSmall?.copyWith(
                  color: strong ? scheme.onTertiary : scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A dashed outline around its box — this device's version of an element in
/// conflict, a draft beside what is.
class _DashedOutline extends CustomPainter {
  _DashedOutline({
    required this.color,
    required this.width,
    required this.dash,
  });

  final Color color;
  final double width;
  final double dash;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = .stroke
      ..strokeWidth = width;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const .circular(HiwiskiMetrics.radiusCard),
        ),
      );
    for (final metric in outline.computeMetrics()) {
      for (double at = 0; at < metric.length; at += dash * 2) {
        canvas.drawPath(metric.extractPath(at, at + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline old) =>
      old.color != color || old.width != width || old.dash != dash;
}

/// The connections: lines from element to element, bent apart where several join the
/// same two, a label on each that has one.
class _EdgesPainter extends CustomPainter {
  _EdgesPainter({
    required this.map,
    required this.origin,
    required this.paints,
    required this.label,
    required this.labelInk,
    required this.background,
    required this.accent,
    required this.highlight,
    required this.selected,
    required this.found,
    required this.conflicts,
    required this.conflictInk,
    required this.pendingLine,
    required this.pendingStyle,
    required this.pendingInk,
    required this.pendingWidth,
    required this.zoom,
    required this.cull,
  });

  final Mindmap map;
  final Offset origin;
  final Map<String, MindmapPaint> paints;

  /// Where the dashes of a dashed or dotted line are worked out — in the map's units;
  /// `null`: along the whole line.
  final Rect? cull;
  final TextStyle label;
  final Color labelInk;

  /// The canvas behind a label, so the line does not run through its text.
  final Color background;
  final Color accent;
  final Color highlight;
  final Set<String> selected;
  final Set<String> found;
  final Set<String> conflicts;
  final Color conflictInk;
  final (Offset, Offset)? pendingLine;
  final MindmapEdgeStyle? pendingStyle;
  final Color pendingInk;

  /// Its own thickness, in the map's units; `null` for the app's own.
  final double? pendingWidth;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(-origin.dx, -origin.dy);
    final minHead = HiwiskiMetrics.mindmapArrowHead / zoom;
    for (final edge in map.edges) {
      final path = edgePathOf(map, edge, HiwiskiMetrics.mindmapEdgeSpread);
      if (path == null) continue;
      final isSelected = selected.contains(edge.id);
      final color = switch ((isSelected, found.contains(edge.id))) {
        (true, _) => accent,
        (false, true) => highlight,
        _ => paints[edge.id]?.line ?? labelInk,
      };
      // A thickness of its own is the map's, zoomed with it; the app's own keeps a
      // visible width when zoomed far out.
      final own = edge.strokeWidth?.toDouble();
      final thickness = own == null
          ? (isSelected
                    ? HiwiskiMetrics.strokeBold * 2
                    : HiwiskiMetrics.strokeBold) /
                zoom.clamp(_minLineZoom, 1)
          : own + (isSelected ? HiwiskiMetrics.strokeBold * 2 / zoom : 0);
      final line = Paint()
        ..color = color
        ..style = .stroke
        ..strokeCap = .round
        ..strokeWidth = thickness;
      // A quadratic curve through the bend: its control point lies twice as far out.
      final middle = (path.start + path.end) / 2;
      paintMindmapLine(
        canvas,
        start: path.start,
        control: path.bend * 2 - middle,
        end: path.end,
        paint: line,
        style: (line: edge.line, arrows: edge.arrows),
        minHead: minHead,
        cull: cull,
      );
      if (edge.text.isNotEmpty || conflicts.contains(edge.id)) {
        _label(canvas, edge, path.bend, color);
      }
    }
    if (pendingLine case (final from, final to)) {
      paintMindmapLine(
        canvas,
        start: from,
        control: (from + to) / 2,
        end: to,
        paint: Paint()
          ..color = pendingInk
          ..style = .stroke
          ..strokeCap = .round
          ..strokeWidth = pendingWidth ?? HiwiskiMetrics.strokeBold / zoom,
        style: pendingStyle ?? (line: null, arrows: null),
        minHead: minHead,
      );
    }
  }

  void _label(Canvas canvas, MindmapEdge edge, Offset at, Color border) {
    final conflict = conflicts.contains(edge.id);
    final text = TextPainter(
      text: TextSpan(
        text: edge.text.isEmpty ? _conflictMark : edge.text,
        style: label.copyWith(color: conflict ? conflictInk : labelInk),
      ),
      textDirection: .ltr,
      textAlign: .center,
      maxLines: _labelLines,
      ellipsis: _ellipsis,
    )..layout(maxWidth: HiwiskiMetrics.mindmapLabelMaxWidth);
    final box = Rect.fromCenter(
      center: at,
      width: text.width + 2 * HiwiskiMetrics.space8,
      height: text.height + 2 * HiwiskiMetrics.space4,
    );
    final shape = RRect.fromRectAndRadius(
      box,
      const .circular(HiwiskiMetrics.radiusChip),
    );
    canvas
      ..drawRRect(shape, Paint()..color = background)
      ..drawRRect(
        shape,
        Paint()
          ..color = conflict ? conflictInk : border
          ..style = .stroke
          ..strokeWidth = HiwiskiMetrics.hairline,
      );
    text.paint(
      canvas,
      box.topLeft + const Offset(HiwiskiMetrics.space8, HiwiskiMetrics.space4),
    );
    text.dispose();
  }

  static const _labelLines = 3;
  static const _ellipsis = '…';
  static const _conflictMark = '!';

  /// Lines keep a visible width when zoomed far out, but do not grow when zoomed in.
  static const _minLineZoom = 0.5;

  /// Taps go to the canvas, which finds the line under them itself — near it on
  /// screen at every zoom, not on its hairline.
  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_EdgesPainter old) =>
      old.map != map ||
      old.origin != origin ||
      !setEquals(old.selected, selected) ||
      !setEquals(old.found, found) ||
      !setEquals(old.conflicts, conflicts) ||
      old.pendingLine != pendingLine ||
      old.pendingStyle != pendingStyle ||
      old.pendingInk != pendingInk ||
      old.pendingWidth != pendingWidth ||
      old.zoom != zoom ||
      old.cull != cull ||
      old.labelInk != labelInk ||
      old.background != background;
}
