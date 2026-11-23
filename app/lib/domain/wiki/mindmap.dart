import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

import '../../core/api/generated/export.dart' show Member;

import '../../core/common/app_names.dart';
import '../../core/common/wire.dart';
import '../common/change.dart';
import '../links/link_index.dart';
import '../links/link_text.dart';
import '../sync/sync_items.dart';
import 'page_images.dart';

// A mind map is a wiki page of the kind MINDMAP; its elements and connections are items
// of their own in that page (see docs/development/wiki-page-kinds.md). These are the
// models and the pure rules: stacking, geometry, search. The canvas draws them, the
// ViewModel decides with them.

/// An element on the canvas.
class MindmapNode {
  const MindmapNode({
    required this.id,
    required this.ownerId,
    required this.version,
    required this.pageId,
    required this.kind,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.layer,
    required this.text,
    this.target,
    this.linkView,
    this.color,
    this.shape,
    this.textSize,
    this.textColor,
    this.points,
    this.strokeWidth,
    this.rotation,
  });

  final String id;
  final String ownerId;
  final int version;
  final String pageId;

  /// [MindmapKinds]; an unknown one is drawn as a placeholder.
  final String kind;
  final int x;
  final int y;
  final int width;
  final int height;

  /// Higher above lower; on a tie the later id is above ([stacked]).
  final double layer;

  /// Plain text, Markdown for a note, a picture element's picture as a Markdown
  /// image — the way a page's text holds one.
  final String text;

  /// `hiwiski://<type>/<id>` for a link element.
  final String? target;

  /// What a link element shows of its target ([MindmapLinkViews]); `null`: the title.
  final String? linkView;

  /// Whether a link element shows its target's content, as its preview does.
  bool get showsContent => linkView == MindmapLinkViews.content;

  /// The picture a picture element shows — the first, should its text hold more.
  String? get imageId => [
    for (final segment in pageSegments(text))
      if (segment case ImageGroup(:final imageIds)) ...imageIds,
  ].firstOrNull;

  /// An accent token or `#RRGGBB` ([MindmapColor]); `null` for the theme's own.
  final String? color;

  /// [MindmapShapes]; `null` or unknown: the kind's own.
  final String? shape;

  /// [MindmapTextSizes]; `null`: medium.
  final String? textSize;

  /// The colour of its text, given as [color] is; `null`: the theme's own, or on a
  /// coloured surface the ink that reads best on it.
  final String? textColor;

  /// A drawing element's stroke: its points across the element ([strokeOf]).
  final String? points;

  /// How thick a drawing element's stroke is, in the map's units.
  final int? strokeWidth;

  /// How far it is turned clockwise about its centre, in whole degrees 0–359;
  /// `null`: not turned.
  final int? rotation;

  /// [rotation] in radians, 0 for none.
  double get turn => (rotation ?? 0) * math.pi / _halfTurn;

  /// The box it covers on the map as it is turned.
  Rect get turnedBounds {
    if (turn == 0) return bounds;
    final half = Offset(width / 2, height / 2);
    final corners = [
      for (final corner in [
        Offset(-half.dx, -half.dy),
        Offset(half.dx, -half.dy),
        Offset(half.dx, half.dy),
        Offset(-half.dx, half.dy),
      ])
        center + turnOffset(corner, turn),
    ];
    double least(double Function(Offset) of) =>
        corners.map(of).fold(double.infinity, math.min);
    double most(double Function(Offset) of) =>
        corners.map(of).fold(double.negativeInfinity, math.max);
    return .fromLTRB(
      least((point) => point.dx),
      least((point) => point.dy),
      most((point) => point.dx),
      most((point) => point.dy),
    );
  }

  /// Whether [point] of the map lies on it, as it is turned.
  bool covers(Offset point) =>
      bounds.contains(center + turnOffset(point - center, -turn));

  /// The element at [width] × [height]. Turned, its top left corner — as it is seen
  /// — stays where it is: grown from the unturned corner, the element slid away
  /// from the grip being dragged.
  MindmapNode resizedTo(int width, int height) {
    if (turn == 0) return changed(width: width, height: height);
    final grown = Offset((width - this.width) / 2, (height - this.height) / 2);
    final middle = center + turnOffset(grown, turn);
    return changed(
      x: (middle.dx - width / 2).round(),
      y: (middle.dy - height / 2).round(),
      width: width,
      height: height,
    );
  }

  /// What a drawing element was drawn as — `null` for a stroke drawn freehand, and
  /// for any other element.
  MindmapPenShape? get penShape => kind != MindmapKinds.drawing
      ? null
      : MindmapPenShape.values
            .where((each) => penShapeName(each) == shape)
            .firstOrNull;

  Rect get bounds => .fromLTWH(
    x.toDouble(),
    y.toDouble(),
    width.toDouble(),
    height.toDouble(),
  );

  Offset get center => bounds.center;

  bool get isKnownKind => const {
    MindmapKinds.plain,
    MindmapKinds.note,
    MindmapKinds.image,
    MindmapKinds.link,
    MindmapKinds.member,
    MindmapKinds.drawing,
  }.contains(kind);

  /// The outline it is drawn with: a plain snippet has none by default, the others a
  /// rounded box.
  String get effectiveShape => switch (shape) {
    final known?
        when const {
          MindmapShapes.rectangle,
          MindmapShapes.rounded,
          MindmapShapes.ellipse,
          MindmapShapes.pill,
          MindmapShapes.diamond,
        }.contains(known) =>
      known,
    _ => MindmapShapes.rounded,
  };

  /// Whether it is drawn on a surface of its own. A snippet of text stands on the
  /// canvas itself, its colour its text's; a picture element is its picture, a
  /// member's their round picture in a ring of the element's colour.
  bool get hasSurface =>
      kind != MindmapKinds.plain &&
      kind != MindmapKinds.image &&
      kind != MindmapKinds.member &&
      kind != MindmapKinds.drawing;

  /// Whether it keeps its shape when resized: a picture its own, a member's circle
  /// its roundness.
  bool get keepsShape =>
      kind == MindmapKinds.image || kind == MindmapKinds.member;

  MindmapNode moved(Offset delta) =>
      changed(x: (x + delta.dx).round(), y: (y + delta.dy).round());

  /// The same element with what a gesture or an edit changed — for drawing it while
  /// the change is under way.
  MindmapNode changed({
    int? x,
    int? y,
    int? width,
    int? height,
    double? layer,
    String? text,
  }) => .new(
    id: id,
    ownerId: ownerId,
    version: version,
    pageId: pageId,
    kind: kind,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    layer: layer ?? this.layer,
    text: text ?? this.text,
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

  /// The fields [other] holds otherwise, by their names on the wire — what a change
  /// from this element to [other] writes, and all that taking it back writes again.
  Set<String> fieldsChangedTo(MindmapNode other) => {
    if (other.x != x) WireFields.x,
    if (other.y != y) WireFields.y,
    if (other.width != width) WireFields.width,
    if (other.height != height) WireFields.height,
    if (other.layer != layer) WireFields.layer,
    if (other.text != text) WireFields.text,
    if (other.target != target) WireFields.target,
    if (other.linkView != linkView) WireFields.linkView,
    if (other.color != color) WireFields.color,
    if (other.shape != shape) WireFields.shape,
    if (other.textSize != textSize) WireFields.textSize,
    if (other.textColor != textColor) WireFields.textColor,
    if (other.strokeWidth != strokeWidth) WireFields.strokeWidth,
    if (other.rotation != rotation) WireFields.rotation,
  };

  /// The same element with another look or target — `Change(null)` clears one.
  MindmapNode styled({
    Change<String?>? target,
    Change<String?>? linkView,
    Change<String?>? color,
    Change<String?>? shape,
    Change<String?>? textSize,
    Change<String?>? textColor,
    Change<int?>? strokeWidth,
    Change<int?>? rotation,
  }) => .new(
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
    text: text,
    target: target == null ? this.target : target.value,
    linkView: linkView == null ? this.linkView : linkView.value,
    color: color == null ? this.color : color.value,
    shape: shape == null ? this.shape : shape.value,
    textSize: textSize == null ? this.textSize : textSize.value,
    textColor: textColor == null ? this.textColor : textColor.value,
    points: points,
    strokeWidth: strokeWidth == null ? this.strokeWidth : strokeWidth.value,
    rotation: rotation == null ? this.rotation : rotation.value,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MindmapNode &&
          other.id == id &&
          other.ownerId == ownerId &&
          other.version == version &&
          other.pageId == pageId &&
          other.kind == kind &&
          other.x == x &&
          other.y == y &&
          other.width == width &&
          other.height == height &&
          other.layer == layer &&
          other.text == text &&
          other.target == target &&
          other.linkView == linkView &&
          other.color == color &&
          other.shape == shape &&
          other.textSize == textSize &&
          other.textColor == textColor &&
          other.points == points &&
          other.strokeWidth == strokeWidth &&
          other.rotation == rotation;

  @override
  int get hashCode => Object.hash(
    id,
    version,
    kind,
    x,
    y,
    width,
    height,
    layer,
    text,
    target,
    linkView,
    color,
    shape,
    textSize,
    textColor,
    points,
    strokeWidth,
    rotation,
  );
}

const _halfTurn = 180;

/// [degrees] as a node's rotation: whole, 0–359, `null` for none.
int? rotationOf(double degrees) {
  final whole = degrees.round() % (2 * _halfTurn);
  return whole == 0 ? null : whole;
}

/// A connection between two elements, drawn from centre to centre.
class MindmapEdge {
  const MindmapEdge({
    required this.id,
    required this.ownerId,
    required this.version,
    required this.pageId,
    required this.fromId,
    required this.toId,
    required this.text,
    this.color,
    this.strokeWidth,
    this.line,
    this.arrows,
  });

  final String id;
  final String ownerId;
  final int version;
  final String pageId;
  final String fromId;
  final String toId;

  /// The label at the middle of the line.
  final String text;

  /// An accent token or `#RRGGBB`; `null` for the theme's line colour.
  final String? color;

  /// How thick the line is, in the map's units; `null` for the app's own.
  final int? strokeWidth;

  /// The line drawn ([MindmapLines]) and where it has arrow heads
  /// ([MindmapArrows]); `null`: solid, without heads.
  final String? line;
  final String? arrows;

  /// Whether it joins [a] and [b], either way round.
  bool joins(String a, String b) =>
      (fromId == a && toId == b) || (fromId == b && toId == a);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MindmapEdge &&
          other.id == id &&
          other.ownerId == ownerId &&
          other.version == version &&
          other.pageId == pageId &&
          other.fromId == fromId &&
          other.toId == toId &&
          other.text == text &&
          other.color == color &&
          other.strokeWidth == strokeWidth &&
          other.line == line &&
          other.arrows == arrows;

  @override
  int get hashCode => Object.hash(
    id,
    version,
    fromId,
    toId,
    text,
    color,
    strokeWidth,
    line,
    arrows,
  );
}

/// A page's mind map: its elements bottom to top, and the connections between them.
class Mindmap {
  Mindmap({required List<MindmapNode> nodes, required List<MindmapEdge> edges})
    : nodes = stacked(nodes),
      edges = _drawable(edges, {for (final node in nodes) node.id});

  static final empty = Mindmap(nodes: const [], edges: const []);

  /// Bottom to top.
  final List<MindmapNode> nodes;

  /// Only those whose two ends are here: one whose element is gone on this device —
  /// deleted, not arrived yet — would point at nothing.
  final List<MindmapEdge> edges;

  late final Map<String, MindmapNode> _byId = {
    for (final node in nodes) node.id: node,
  };

  bool get isEmpty => nodes.isEmpty;

  /// The same map with [changed] drawn where a gesture under way has them — the
  /// stored elements stay as they are until it ends.
  /// The same map with [node] on it too — one not written yet, drawn meanwhile.
  Mindmap plus(MindmapNode node) => .new(nodes: [...nodes, node], edges: edges);

  Mindmap withNodes(Map<String, MindmapNode> changed) => changed.isEmpty
      ? this
      : .new(
          nodes: [for (final node in nodes) changed[node.id] ?? node],
          edges: edges,
        );

  MindmapNode? node(String id) => _byId[id];

  MindmapEdge? edge(String id) =>
      edges.where((edge) => edge.id == id).firstOrNull;

  /// Everything drawn, or `null` for an empty map.
  Rect? get bounds {
    if (nodes.isEmpty) return null;
    return nodes
        .map((node) => node.turnedBounds)
        .reduce((all, next) => all.expandToInclude(next));
  }

  /// The layer an element created now goes on: above all.
  double get topLayer => nodes.isEmpty ? 1 : nodes.last.layer + 1;

  /// Connections drawn between the same two elements — the index of [edge] among
  /// them and how many there are. Two people may connect the same pair offline, each
  /// with a label; both are drawn, bent apart, so neither label hides the other.
  (int, int) siblingsOf(MindmapEdge edge) {
    final same = [
      for (final other in edges)
        if (other.joins(edge.fromId, edge.toId)) other.id,
    ];
    return (same.indexOf(edge.id), same.length);
  }

  static List<MindmapNode> stacked(List<MindmapNode> nodes) =>
      [...nodes]..sort((a, b) {
        final byLayer = a.layer.compareTo(b.layer);
        return byLayer != 0 ? byLayer : a.id.compareTo(b.id);
      });

  static List<MindmapEdge> _drawable(
    List<MindmapEdge> edges,
    Set<String> present,
  ) => [
    for (final edge in edges)
      if (present.contains(edge.fromId) &&
          present.contains(edge.toId) &&
          edge.fromId != edge.toId)
        edge,
  ];
}

// --- Stacking ------------------------------------------------------------------

/// The layer that puts [node] one step up — above the next element *overlapping* it,
/// below whatever was above that one. `null` when nothing that overlaps it lies above.
///
/// One step past the next overlapping element, not the next in the whole map: that
/// one may lie far away, and the step would change nothing anyone can see.
double? layerUp(Mindmap map, MindmapNode node) {
  final others = [
    for (final other in map.nodes)
      if (other.id != node.id) other,
  ];
  final at = map.nodes.indexWhere((other) => other.id == node.id);
  if (at < 0) return null;
  final above = map.nodes
      .skip(at + 1)
      .where((other) => other.bounds.overlaps(node.bounds));
  final step = above.firstOrNull;
  if (step == null) return null;
  final after = others.skipWhile((other) => other.id != step.id).skip(1);
  return _between(step.layer, after.firstOrNull?.layer, up: true);
}

/// The layer that puts [node] one step down — below the next overlapping element
/// under it. `null` when nothing that overlaps it lies below.
double? layerDown(Mindmap map, MindmapNode node) {
  final others = [
    for (final other in map.nodes)
      if (other.id != node.id) other,
  ];
  final at = map.nodes.indexWhere((other) => other.id == node.id);
  if (at < 0) return null;
  final below = map.nodes
      .take(at)
      .toList()
      .reversed
      .where((other) => other.bounds.overlaps(node.bounds));
  final step = below.firstOrNull;
  if (step == null) return null;
  final before = others.reversed
      .skipWhile((other) => other.id != step.id)
      .skip(1);
  return _between(step.layer, before.firstOrNull?.layer, up: false);
}

/// Above everything else — `null` when it is there already.
double? layerToFront(Mindmap map, MindmapNode node) {
  final top = map.nodes.lastOrNull;
  if (top == null || top.id == node.id) return null;
  return top.layer + 1;
}

/// Below everything else — `null` when it is there already.
double? layerToBack(Mindmap map, MindmapNode node) {
  final bottom = map.nodes.firstOrNull;
  if (bottom == null || bottom.id == node.id) return null;
  return bottom.layer - 1;
}

/// Halfway between [step] and its neighbour on the far side — or a whole step past
/// [step] when there is none. Two elements on the same layer (created offline on two
/// devices at once) leave no room between them: then just past [step].
double _between(double step, double? beyond, {required bool up}) {
  final sign = up ? 1 : -1;
  if (beyond == null) return step + sign;
  final middle = (step + beyond) / 2;
  if (middle == step || middle == beyond) {
    return step + sign * _smallestStep;
  }
  return middle;
}

const _smallestStep = 1e-9;

// --- Geometry ------------------------------------------------------------------

/// Where a connection's line runs: from [from]'s centre to [to]'s, cut at their
/// outlines so it starts and ends at the edge of each. A turned element's outline is
/// taken as it would be unturned: the line still runs from centre to centre, only
/// its end may stop a little short of the edge or cross it. `null` while they overlap so
/// far that nothing of the line would show.
(Offset, Offset)? edgeLine(MindmapNode from, MindmapNode to) {
  final a = from.center;
  final b = to.center;
  final start = _exit(from, b);
  final end = _exit(to, a);
  final direction = b - a;
  double along(Offset point) =>
      (point - a).dx * direction.dx + (point - a).dy * direction.dy;
  if (direction.distanceSquared == 0 || along(start) >= along(end)) {
    return null;
  }
  return (start, end);
}

/// Where the ray from [node]'s centre towards [towards] leaves its outline.
Offset _exit(MindmapNode node, Offset towards) {
  final center = node.center;
  final d = towards - center;
  if (d.distanceSquared == 0) return center;
  final hw = node.width / 2;
  final hh = node.height / 2;
  final double t;
  switch (node.hasSurface ? node.effectiveShape : MindmapShapes.rectangle) {
    case MindmapShapes.ellipse:
      t = 1 / math.sqrt((d.dx * d.dx) / (hw * hw) + (d.dy * d.dy) / (hh * hh));
    case MindmapShapes.diamond:
      t = 1 / (d.dx.abs() / hw + d.dy.abs() / hh);
    default:
      final tx = d.dx == 0 ? double.infinity : hw / d.dx.abs();
      final ty = d.dy == 0 ? double.infinity : hh / d.dy.abs();
      t = math.min(tx, ty);
  }
  return center + d * math.min(t, 1);
}

/// The way a connection is drawn: from [start] through [bend] to [end] — a straight
/// line when [bend] is its middle. `null` while its elements overlap too far.
typedef EdgePath = ({Offset start, Offset bend, Offset end});

EdgePath? edgePathOf(Mindmap map, MindmapEdge edge, double spread) {
  final from = map.node(edge.fromId);
  final to = map.node(edge.toId);
  if (from == null || to == null) return null;
  final line = edgeLine(from, to);
  if (line == null) return null;
  final (start, end) = line;
  final (index, count) = map.siblingsOf(edge);
  // Bent the same way whichever end it was drawn from.
  final forward = edge.fromId.compareTo(edge.toId) < 0;
  final bend = forward
      ? bendOf(start, end, index, count, spread)
      : bendOf(end, start, index, count, spread);
  return (start: start, bend: bend, end: end);
}

/// How far [point] lies from [path] — for a tap on a line.
double distanceToPath(Offset point, EdgePath path) => math.min(
  distanceToSegment(point, path.start, path.bend),
  distanceToSegment(point, path.bend, path.end),
);

/// How far [point] lies from the segment [start]–[end] — for a tap on a line.
double distanceToSegment(Offset point, Offset start, Offset end) {
  final segment = end - start;
  final length = segment.distanceSquared;
  if (length == 0) return (point - start).distance;
  final along =
      ((point - start).dx * segment.dx + (point - start).dy * segment.dy) /
      length;
  final t = along.clamp(0.0, 1.0);
  return (point - (start + segment * t)).distance;
}

/// The point a connection bends through when [count] lines join the same two elements:
/// the middle of the line for one, pushed apart sideways for more.
Offset bendOf(Offset start, Offset end, int index, int count, double spread) {
  final middle = (start + end) / 2;
  if (count < 2) return middle;
  final along = end - start;
  final length = along.distance;
  if (length == 0) return middle;
  final normal = Offset(-along.dy / length, along.dx / length);
  final offset = (index - (count - 1) / 2) * spread;
  return middle + normal * offset;
}

/// The camera that shows all of [content] in [viewport], with [margin] around it, no
/// closer than [maxScale].
({double scale, Offset origin}) fitInto(
  Rect content,
  Size viewport, {
  double margin = 0,
  double maxScale = 1,
  double minScale = 0.05,
}) {
  final width = math.max(content.width + 2 * margin, 1);
  final height = math.max(content.height + 2 * margin, 1);
  final scale = math
      .min(viewport.width / width, viewport.height / height)
      .clamp(minScale, maxScale);
  // The content's centre at the viewport's centre.
  final origin = Offset(
    viewport.width / 2 - content.center.dx * scale,
    viewport.height / 2 - content.center.dy * scale,
  );
  return (scale: scale, origin: origin);
}

// --- Colour ----------------------------------------------------------------------

/// A colour as stored: an accent token the theme maps, or the family's own as
/// `#RRGGBB` — `#RRGGBBAA` where it lets the canvas show through — which the theme
/// adapts so that it reads in light and in dark.
sealed class MindmapColor {
  const MindmapColor();

  /// `null` for an empty or unreadable value — the theme's own colour then.
  static MindmapColor? parse(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    final own = _rgb.firstMatch(stored);
    if (own?.group(1) case final hex?) {
      return OwnColor(
        int.parse(hex, radix: 16),
        alpha: switch (own?.group(2)) {
          final alpha? => int.parse(alpha, radix: 16),
          null => OwnColor.opaque,
        },
      );
    }
    if (_token.hasMatch(stored)) return TokenColor(stored);
    return null;
  }

  /// How it is stored.
  String get stored;

  static final _rgb = RegExp(r'^#([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?$');
  static final _token = RegExp(r'^[A-Z][A-Z_]{0,31}$');
}

/// One of the accent tokens — `BLUE`, `RUST`, … — or one this app does not know yet.
final class TokenColor extends MindmapColor {
  const TokenColor(this.token);

  final String token;

  @override
  String get stored => token;

  @override
  bool operator ==(Object other) => other is TokenColor && other.token == token;

  @override
  int get hashCode => token.hashCode;
}

/// A colour of the family's own, `0xRRGGBB`, and how much of it covers what lies
/// under it: [alpha] from 0, see-through, to [opaque].
final class OwnColor extends MindmapColor {
  const OwnColor(this.rgb, {this.alpha = opaque});

  final int rgb;
  final int alpha;

  static const opaque = 0xFF;

  /// Whether the canvas shows through it.
  bool get seeThrough => alpha < opaque;

  @override
  String get stored => [
    '#',
    _hex(rgb, 6),
    // Opaque as before: an older app reads it, and the same colour is one value.
    if (seeThrough) _hex(alpha, 2),
  ].join();

  static String _hex(int value, int digits) =>
      value.toRadixString(16).padLeft(digits, '0').toUpperCase();

  @override
  bool operator ==(Object other) =>
      other is OwnColor && other.rgb == rgb && other.alpha == alpha;

  @override
  int get hashCode => Object.hash(rgb, alpha);
}

// --- Search ----------------------------------------------------------------------

/// What a search on the page found: an element or a connection, and the words around
/// the match.
class MindmapHit {
  const MindmapHit({
    required this.id,
    required this.isEdge,
    required this.kind,
    required this.snippet,
    required this.bounds,
    this.text = '',
  });

  final String id;
  final bool isEdge;

  /// The whole text the match was found in — what the hits are put in order by,
  /// alphabetically.
  final String text;

  /// The element's kind; for a connection [MindmapKinds.plain].
  final String kind;

  /// The text the match was found in, shortened around it.
  final String snippet;

  /// Where on the canvas to go: the element, or the middle of the connection.
  final Rect bounds;

  @override
  bool operator ==(Object other) =>
      other is MindmapHit &&
      other.id == id &&
      other.isEdge == isEdge &&
      other.snippet == snippet &&
      other.bounds == bounds &&
      other.text == text;

  @override
  int get hashCode => Object.hash(id, isEdge, snippet, bounds, text);
}

/// How the hits of a search are put in order: by where they lie on the map —
/// reading order —, alphabetically, or by when they were made.
enum MindmapHitOrder { place, alphabetical, created }

/// [hits] in [order], the other way round if [descending].
///
/// When an element or a connection was made is in its id: an id is a UUID of
/// version 7, whose first digits are the time it was made — in order as text.
List<MindmapHit> sortHits(
  List<MindmapHit> hits,
  MindmapHitOrder order, {
  required bool descending,
}) {
  int compare(MindmapHit a, MindmapHit b) => switch (order) {
    .place => _byPlace(a, b),
    .alphabetical => switch (a.text.trim().toLowerCase().compareTo(
      b.text.trim().toLowerCase(),
    )) {
      0 => _byPlace(a, b),
      final other => other,
    },
    .created => a.id.compareTo(b.id),
  };
  final sorted = [...hits]..sort(compare);
  return descending ? sorted.reversed.toList() : sorted;
}

int _byPlace(MindmapHit a, MindmapHit b) {
  final row = a.bounds.top.compareTo(b.bounds.top);
  return row != 0 ? row : a.bounds.left.compareTo(b.bounds.left);
}

/// Every element and connection whose text holds [query] — in reading order, top to
/// bottom and left to right. A link element is found by the title of what it points to
/// ([titleOf]). Case is ignored.
List<MindmapHit> searchMindmap(
  Mindmap map,
  String query, {
  required String? Function(String target) titleOf,
}) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  final hits = <MindmapHit>[];
  for (final node in map.nodes) {
    final text = switch (node.kind) {
      MindmapKinds.note => plainOfMarkdown(node.text),
      // Its text is its pictures.
      MindmapKinds.image => '',
      // Found by the title of what it points to, by the name of whom it shows.
      MindmapKinds.link || MindmapKinds.member => [
        node.text,
        if (node.target case final target?) ?titleOf(target),
      ].join(' '),
      _ => node.text,
    };
    final at = text.toLowerCase().indexOf(needle);
    if (at < 0) continue;
    hits.add(
      MindmapHit(
        id: node.id,
        isEdge: false,
        kind: node.kind,
        snippet: snippetAround(text, at, needle.length),
        bounds: node.bounds,
        text: text,
      ),
    );
  }
  for (final edge in map.edges) {
    final at = edge.text.toLowerCase().indexOf(needle);
    final from = map.node(edge.fromId);
    final to = map.node(edge.toId);
    if (at < 0 || from == null || to == null) continue;
    final middle = (from.center + to.center) / 2;
    hits.add(
      MindmapHit(
        id: edge.id,
        isEdge: true,
        kind: MindmapKinds.plain,
        snippet: snippetAround(edge.text, at, needle.length),
        bounds: Rect.fromCenter(center: middle, width: 0, height: 0),
        text: edge.text,
      ),
    );
  }
  return hits..sort(_byPlace);
}

/// [text] shortened to a line around the match at [at].
String snippetAround(String text, int at, int length, {int context = 32}) {
  final flat = text.replaceAll(_whitespace, ' ');
  final start = math.max(0, at - context);
  final end = math.min(flat.length, at + length + context);
  final cut = flat.substring(start, end).trim();
  return '${start > 0 ? _ellipsis : ''}$cut${end < flat.length ? _ellipsis : ''}';
}

const _ellipsis = '…';

final _whitespace = RegExp(r'\s+');

/// What a note reads as without its Markdown — for a snippet and for the canvas from
/// afar, where a rendered note would be too small to read anyway.
String plainOfMarkdown(String markdown) => markdown
    .replaceAll(_imageMarkdown, '')
    .replaceAllMapped(_linkMarkdown, (match) => match.group(1) ?? '')
    .replaceAll(_linePrefix, '')
    .replaceAll(_emphasis, '')
    .trim();

final _imageMarkdown = RegExp(r'!\[[^\]]*\]\([^)]*\)');
final _linkMarkdown = RegExp(r'\[([^\]]*)\]\([^)]*\)');
final _linePrefix = RegExp(
  r'^\s*(#{1,6}\s|[-*+]\s(\[[ xX]\]\s)?|>\s?|\d+\.\s)',
  multiLine: true,
);
final _emphasis = RegExp(r'[*_`~]');

// --- Links -----------------------------------------------------------------------

/// The item a link element's address points to, as the link index knows it — `null`
/// when it is not on this device.
LinkItem? linkItemOf(String target, LinkIndex index) =>
    switch (parseReferences(target).firstOrNull) {
      final reference? => index.resolve(reference),
      null => null,
    };

/// The address of the first item [markdown] links to — what the link picker inserts
/// (`[Title](hiwiski://todo/<id>)`) — as a link element stores it.
String? linkAddressOf(String markdown) =>
    switch (parseReferences(markdown).firstOrNull) {
      UriReference(:final itemType, :final itemId) =>
        '${UriSchemes.hiwiski}://${itemType.toLowerCase()}/$itemId',
      _ => null,
    };

/// A shape drawn with the pen. It is kept as a stroke along its outline — erased,
/// coloured and made thicker like any other.
enum MindmapPenShape { rectangle, ellipse, triangle, diamond, line, arrow }

/// The points of a stroke along [shape], spanning [from] to [to]; an arrow's head is
/// [head] long. A corner is given twice: the stroke is smoothed through the middles
/// of its points, and a corner given once came out rounded.
List<Offset> penShapeOutline(
  MindmapPenShape shape,
  Offset from,
  Offset to, {
  required double head,
}) {
  final box = Rect.fromPoints(from, to);
  List<Offset> cornered(List<Offset> points) => [
    for (final point in points) ...[point, point],
  ];
  switch (shape) {
    case .rectangle:
      return cornered([
        box.topLeft,
        box.topRight,
        box.bottomRight,
        box.bottomLeft,
        box.topLeft,
      ]);
    case .triangle:
      return cornered([
        box.bottomLeft,
        box.topCenter,
        box.bottomRight,
        box.bottomLeft,
      ]);
    case .diamond:
      return cornered([
        box.topCenter,
        box.centerRight,
        box.bottomCenter,
        box.centerLeft,
        box.topCenter,
      ]);
    case .ellipse:
      return [
        for (int step = 0; step <= _ellipseSteps; step++)
          box.center +
              Offset(
                math.cos(step * 2 * math.pi / _ellipseSteps) * box.width / 2,
                math.sin(step * 2 * math.pi / _ellipseSteps) * box.height / 2,
              ),
      ];
    case .line:
      return [from, to];
    case .arrow:
      final along = to - from;
      if (along.distance == 0) return [from];
      final back = -along / along.distance * math.min(head, along.distance / 2);
      Offset wing(double turn) => to + turnOffset(back, turn);
      // Out to the tip, along one side of the head and back, along the other.
      return [
        from,
        to,
        to,
        wing(_headSpread),
        wing(_headSpread),
        to,
        to,
        wing(-_headSpread),
      ];
  }
}

/// How a drawn shape is named in an element's `shape`.
String penShapeName(MindmapPenShape shape) => switch (shape) {
  .rectangle => MindmapShapes.rectangle,
  .ellipse => MindmapShapes.ellipse,
  .triangle => MindmapShapes.triangle,
  .diamond => MindmapShapes.diamond,
  .line => MindmapShapes.line,
  .arrow => MindmapShapes.arrow,
};

/// [vector] turned by [angle], clockwise on screen.
Offset turnOffset(Offset vector, double angle) => .new(
  vector.dx * math.cos(angle) - vector.dy * math.sin(angle),
  vector.dx * math.sin(angle) + vector.dy * math.cos(angle),
);

const _ellipseSteps = 48;

/// How far an arrow's head spreads to either side of its line.
const _headSpread = math.pi / 6;

/// A mind map with what it shows of the rest of the family's things — all it takes
/// to draw it as a picture.
typedef MindmapPicture = ({
  String title,
  Mindmap map,
  Map<String, Member> members,
  Map<String, LinkItem> targets,
});

/// Draws a mind map whole as a PNG.
typedef MindmapDrawing = Future<Uint8List> Function(MindmapPicture picture);

/// What each link element of [map] points to, by its address — as the link index on
/// this device knows it now: its current title, its type. An address whose target is
/// not here — deleted, not shared — is missing; the element says so.
Map<String, LinkItem> mindmapTargetsOf(Mindmap map, LinkIndex index) => {
  for (final node in map.nodes)
    if ((node.kind, node.target) case (MindmapKinds.link, final target?))
      target: ?linkItemOf(target, index),
};

// --- Members ---------------------------------------------------------------------

/// The address a member element keeps of whom it shows.
String memberAddressOf(String memberId) =>
    '${UriSchemes.hiwiski}://$_memberPath/$memberId';

/// The member a member element's [target] names — `null` for any other address.
String? memberIdOf(String? target) => switch (target) {
  final String address when address.startsWith(_memberPrefix) =>
    address.substring(_memberPrefix.length),
  _ => null,
};

const _memberPath = 'member';
const _memberPrefix = '${UriSchemes.hiwiski}://$_memberPath/';

// --- Conflicts ---------------------------------------------------------------------

/// The field a conflict of an element is decided under: its position is one thing to
/// decide, and so is its size — x and y lost against the same move, not against two.
String mindmapConflictGroup(String field) => switch (field) {
  WireFields.y => WireFields.x,
  WireFields.height => WireFields.width,
  _ => field,
};

/// [conflicts] as they are decided: those of one element in one
/// [mindmapConflictGroup] together, in the order the first of each came. Other
/// items' conflicts stay one each.
List<List<SyncConflict>> groupConflicts(List<SyncConflict> conflicts) {
  final groups = <(String, String), List<SyncConflict>>{};
  for (final conflict in conflicts) {
    final field = conflict.entityType == EntityTypes.mindmapNode
        ? mindmapConflictGroup(conflict.field)
        : conflict.id;
    (groups[(conflict.entityId, field)] ??= []).add(conflict);
  }
  return [...groups.values];
}

/// [node] as this device wrote it: each field of [conflicts] — lost against someone
/// else's change, and on the map now as they wrote it — back at this device's value.
MindmapNode mineOf(MindmapNode node, List<SyncConflict> conflicts) {
  int? whole(String field) => switch (_mineOf(conflicts, field)) {
    final num value => value.round(),
    _ => null,
  };
  // A look that lost may have been cleared on this device: `null` is a value then.
  Change<String?>? text(String field) =>
      conflicts.any((conflict) => conflict.field == field)
      ? .new(_mineOf(conflicts, field)?.toString())
      : null;
  return node
      .changed(
        x: whole(WireFields.x),
        y: whole(WireFields.y),
        width: whole(WireFields.width),
        height: whole(WireFields.height),
        layer: switch (_mineOf(conflicts, WireFields.layer)) {
          final num value => value.toDouble(),
          _ => null,
        },
        text: _mineOf(conflicts, WireFields.text)?.toString(),
      )
      .styled(
        target: text(WireFields.target),
        linkView: text(WireFields.linkView),
        color: text(WireFields.color),
        shape: text(WireFields.shape),
        textSize: text(WireFields.textSize),
        textColor: text(WireFields.textColor),
        strokeWidth:
            conflicts.any(
              (conflict) => conflict.field == WireFields.strokeWidth,
            )
            ? Change(whole(WireFields.strokeWidth))
            : null,
      );
}

/// Where this device's version of [node] is shown beside the map's: where it was
/// left, or — when only its look differs — just to the right of it, so the two can be
/// told apart.
Rect mineBoundsOf(MindmapNode node, MindmapNode mine, double gap) =>
    mine.bounds == node.bounds
    ? mine.bounds.translate(node.width + gap, 0)
    : mine.bounds;

Object? _mineOf(List<SyncConflict> conflicts, String field) {
  for (final conflict in conflicts) {
    if (conflict.field != field) continue;
    final json = conflict.mine;
    if (json == null) return null;
    try {
      return jsonDecode(json);
    } on FormatException {
      // Stored before values were kept as JSON: the text itself.
      return json;
    }
  }
  return null;
}

/// What a link element's address reads as in a conflict: the target's title and its
/// number, as its preview names it — `null` when the target is not on this device.
String? targetLabelOf(String address, LinkIndex index) {
  final item = linkItemOf(address, index);
  if (item == null) return null;
  return switch (item.entityKey) {
    final key? => '${item.title}$_keySeparator$key',
    null => item.title,
  };
}

const _keySeparator = ' · ';

/// The order the fields of a position or a size are read in.
const _axes = [WireFields.x, WireFields.y, WireFields.width, WireFields.height];

/// [group] — conflicts of one [mindmapConflictGroup] — in the order its fields are
/// read: x before y, width before height.
List<SyncConflict> inReadingOrder(List<SyncConflict> group) => [...group]
  ..sort((a, b) => _axes.indexOf(a.field).compareTo(_axes.indexOf(b.field)));

// --- Strokes drawn by hand -------------------------------------------------------

/// The resolution a stroke's points are stored at, across its element.
const strokeScale = 10000;

/// The longest a stroke's points may be written — the server refuses a longer one.
const mindmapMaxPointsChars = 100000;

/// [points] — a stroke as it was drawn, in the map's units — as a drawing element
/// keeps it: its bounds, wide enough for a line [width] thick, and the points across
/// them. A single point is a dot.
///
/// A stroke too long to keep is thinned out harder until it fits: it loses detail,
/// never its ends. Kept as drawn, the server refused it, and the stroke stood only on
/// the device that drew it.
({Rect bounds, String points}) strokeOf(List<Offset> points, double width) {
  final Offset first = points.firstOrNull ?? .zero;
  double left = first.dx, top = first.dy, right = first.dx, bottom = first.dy;
  for (final point in points) {
    left = math.min(left, point.dx);
    top = math.min(top, point.dy);
    right = math.max(right, point.dx);
    bottom = math.max(bottom, point.dy);
  }
  final bounds = Rect.fromLTRB(
    left,
    top,
    right,
    bottom,
  ).inflate(math.max(width / 2, 1));
  String coordinate(double at, double from, double extent) =>
      ((at - from) / extent * strokeScale)
          .round()
          .clamp(0, strokeScale)
          .toString();
  String written(List<Offset> kept) => [
    for (final point in kept)
      '${coordinate(point.dx, bounds.left, bounds.width)}$_coordinateSeparator'
          '${coordinate(point.dy, bounds.top, bounds.height)}',
  ].join(_pointSeparator);
  List<Offset> kept = points.isEmpty ? [first] : points;
  String stored = written(kept);
  // From what a stored point can tell apart at all, twice as coarse each time; a
  // tolerance beyond the whole stroke leaves its two ends, which always fit.
  double tolerance = bounds.longestSide / strokeScale;
  while (stored.length > mindmapMaxPointsChars) {
    kept = thinOut(kept, tolerance);
    stored = written(kept);
    tolerance *= 2;
  }
  return (bounds: bounds, points: stored);
}

/// A drawing element's stroke as fractions of its element, 0 to 1 across — read once
/// for each stored value: it is drawn in every frame of a zoom.
List<Offset> strokeFractionsOf(String? stored) {
  if (stored == null || stored.isEmpty) return const [];
  final known = _fractions[stored];
  if (known != null) return known;
  final fractions = <Offset>[];
  for (final point in stored.split(_pointSeparator)) {
    final at = point.indexOf(_coordinateSeparator);
    final x = int.tryParse(point.substring(0, math.max(0, at)));
    final y = int.tryParse(point.substring(at + 1));
    if (at < 0 || x == null || y == null) continue;
    fractions.add(Offset(x / strokeScale, y / strokeScale));
  }
  if (_fractions.length >= _fractionsKept) {
    _fractions.remove(_fractions.keys.first);
  }
  return _fractions[stored] = fractions;
}

final _fractions = <String, List<Offset>>{};
const _fractionsKept = 2000;
const _pointSeparator = ' ';
const _coordinateSeparator = ',';

/// A drawing element's stroke in the map's units — where its element stands now.
List<Offset> strokePointsOf(MindmapNode node) => [
  for (final fraction in strokeFractionsOf(node.points))
    Offset(
      node.x + fraction.dx * node.width,
      node.y + fraction.dy * node.height,
    ),
];

/// [points] with fewer of them, none further than [tolerance] from the line they
/// drew (Ramer–Douglas–Peucker): a stroke keeps its shape and loses the points a
/// hand puts down in every frame.
List<Offset> thinOut(List<Offset> points, double tolerance) {
  if (points.length < 3) return points;
  final keep = List.filled(points.length, false)
    ..first = true
    ..last = true;
  final spans = [(0, points.length - 1)];
  while (spans.isNotEmpty) {
    final (from, to) = spans.removeLast();
    double furthest = 0;
    int at = -1;
    for (int i = from + 1; i < to; i++) {
      final distance = distanceToSegment(points[i], points[from], points[to]);
      if (distance > furthest) {
        furthest = distance;
        at = i;
      }
    }
    if (at >= 0 && furthest > tolerance) {
      keep[at] = true;
      spans
        ..add((from, at))
        ..add((at, to));
    }
  }
  return [
    for (int i = 0; i < points.length; i++)
      if (keep[i]) points[i],
  ];
}

/// How far [at] is from the line through [points], in the map's units.
double distanceToStroke(Offset at, List<Offset> points) {
  if (points.isEmpty) return .infinity;
  if (points.length == 1) return (at - points.single).distance;
  double nearest = .infinity;
  for (int i = 1; i < points.length; i++) {
    nearest = math.min(
      nearest,
      distanceToSegment(at, points[i - 1], points[i]),
    );
  }
  return nearest;
}

/// The drawing elements a swipe of the eraser along [path] touches — within [reach]
/// of their line, its thickness counted. Between two points of the swipe the eraser
/// is followed in steps of [reach], so a quick swipe misses nothing it crossed.
Set<String> erasedBy(List<Offset> path, Mindmap map, double reach) {
  final along = <Offset>[];
  for (int i = 0; i < path.length; i++) {
    if (i > 0) {
      final from = path[i - 1];
      final step = path[i] - from;
      final steps = (step.distance / math.max(reach, 1)).ceil();
      for (int s = 1; s < steps; s++) {
        along.add(from + step * (s / steps));
      }
    }
    along.add(path[i]);
  }
  return {
    for (final node in map.nodes)
      if (node.kind == MindmapKinds.drawing)
        if (along.any(
          (at) =>
              node.bounds.inflate(reach).contains(at) &&
              distanceToStroke(at, strokePointsOf(node)) <=
                  reach + (node.strokeWidth ?? 1) / 2,
        ))
          node.id,
  };
}

// --- Sizes of one's own ------------------------------------------------------------

/// A text size of its own, in logical pixels — `null` for one of the names
/// ([MindmapTextSizes]) or none.
int? mindmapTextPixels(String? size) => switch (int.tryParse(size ?? '')) {
  final int pixels
      when pixels >= mindmapMinTextPixels && pixels <= mindmapMaxTextPixels =>
    pixels,
  _ => null,
};

/// The text sizes of one's own the server takes.
const mindmapMinTextPixels = 4;
const mindmapMaxTextPixels = 400;

/// The thickness of a line or a stroke of one's own the server takes.
const mindmapMaxStrokeWidth = 1000;

/// The widest and highest an element may be, in the map's units — the server refuses
/// a larger one.
const mindmapMaxSize = 100000;

// --- Selecting several -------------------------------------------------------------

/// The elements a lasso drawn along [path] goes round — each by its middle, the
/// path closed from its end back to its start. Fewer than three points go round
/// nothing.
Set<String> insideLasso(Mindmap map, List<Offset> path) {
  if (path.length < 3) return const {};
  return {
    for (final node in map.nodes)
      if (_inPolygon(node.center, path)) node.id,
  };
}

/// The elements whose middle lies in the rectangle between [from] and [to].
Set<String> insideRectangle(Mindmap map, Offset from, Offset to) {
  final area = Rect.fromPoints(from, to);
  return {
    for (final node in map.nodes)
      if (area.contains(node.center)) node.id,
  };
}

/// Whether [point] lies inside the polygon [corners] — counted by how many of its
/// sides a ray to the right crosses.
bool _inPolygon(Offset point, List<Offset> corners) {
  bool inside = false;
  for (int i = 0, j = corners.length - 1; i < corners.length; j = i++) {
    final a = corners[i];
    final b = corners[j];
    final crosses =
        (a.dy > point.dy) != (b.dy > point.dy) &&
        point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx;
    if (crosses) inside = !inside;
  }
  return inside;
}
