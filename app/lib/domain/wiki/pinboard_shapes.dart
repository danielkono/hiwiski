import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import '../../core/common/wire.dart';

/// The room across an outline at a height, from [left] to [right].
typedef PinboardAcross = ({double left, double right});

/// The geometry of an element's outline drawn in a box: how far a connection reaches
/// towards it, how wide it is at a height — for lines that follow it — and the same
/// outline a margin inside it.
///
/// One entry per outline ([pinboardShapeOf]); how it is drawn and named is its look
/// (`PinboardElementView.shapeLookOf`). A new outline is described in both, and its
/// name is a constant of `PinboardShapes` (docs/development/pinboard.md).
final class const PinboardShape({
  /// How far along [direction] — from the middle of a box whose half size is
  /// [half] — the outline is: 1 at the box's edge. Where a connection meets it.
  required final double Function(Offset direction, Offset half) reach,

  /// The room across the outline drawn in [box] at height [y]. [corner] is how far a
  /// rounded rectangle's corners are rounded.
  required final PinboardAcross Function(Rect box, double y, double corner)
  across,

  /// The box the same outline [pad] inside the one drawn in [box] is drawn in.
  final Rect Function(Rect box, double pad) inside = _deflated,
});

/// The geometry of the outline [shape]; an unknown one is a rounded rectangle.
PinboardShape pinboardShapeOf(String shape) => _shapes[shape] ?? _rounded;

/// Whether this app knows the outline [shape].
bool knowsPinboardShape(String shape) => _shapes.containsKey(shape);

/// The outlines an element can be given, in the order they are offered.
Iterable<String> get pinboardShapes => _shapes.keys;

const _rounded = PinboardShape(reach: _boxReach, across: _roundedAcross);

const _shapes = <String, PinboardShape>{
  PinboardShapes.rounded: _rounded,
  PinboardShapes.rectangle: PinboardShape(reach: _boxReach, across: _boxAcross),
  // The ends are half circles as wide as the shorter side.
  PinboardShapes.pill: PinboardShape(reach: _boxReach, across: _pillAcross),
  PinboardShapes.ellipse: PinboardShape(
    reach: _ellipseReach,
    across: _ellipseAcross,
  ),
  // Its corners on the middles of its box's sides.
  PinboardShapes.diamond: PinboardShape(
    reach: _diamondReach,
    across: _diamondAcross,
    inside: _diamondInside,
  ),
};

Rect _deflated(Rect box, double pad) => box.deflate(pad);

double _boxReach(Offset direction, Offset half) => math.min(
  direction.dx == 0 ? double.infinity : half.dx / direction.dx.abs(),
  direction.dy == 0 ? double.infinity : half.dy / direction.dy.abs(),
);

double _ellipseReach(Offset direction, Offset half) =>
    1 /
    math.sqrt(
      (direction.dx * direction.dx) / (half.dx * half.dx) +
          (direction.dy * direction.dy) / (half.dy * half.dy),
    );

double _diamondReach(Offset direction, Offset half) =>
    1 / (direction.dx.abs() / half.dx + direction.dy.abs() / half.dy);

PinboardAcross _boxAcross(Rect box, double y, double corner) =>
    (left: box.left, right: box.right);

PinboardAcross _roundedAcross(Rect box, double y, double corner) =>
    _roundedAt(box, y, corner);

PinboardAcross _pillAcross(Rect box, double y, double corner) =>
    _roundedAt(box, y, math.min(box.width, box.height) / 2);

PinboardAcross _ellipseAcross(Rect box, double y, double corner) {
  final middle = box.center;
  final off = (y - middle.dy) / (box.height / 2);
  final half = box.width / 2 * math.sqrt(math.max(0, 1 - off * off));
  return (left: middle.dx - half, right: middle.dx + half);
}

PinboardAcross _diamondAcross(Rect box, double y, double corner) {
  final middle = box.center;
  final off = (y - middle.dy).abs() / (box.height / 2);
  final half = box.width / 2 * math.max(0, 1 - off);
  return (left: middle.dx - half, right: middle.dx + half);
}

/// A diamond shrinks about its middle: [pad] off its slanted sides takes more off
/// its corners.
Rect _diamondInside(Rect box, double pad) {
  final across = box.width / 2;
  final upDown = box.height / 2;
  if (across <= 0 || upDown <= 0) return .zero;
  final slant = math.sqrt(across * across + upDown * upDown);
  final scale = 1 - pad * slant / (across * upDown);
  if (scale <= 0) return .zero;
  return .fromCenter(
    center: box.center,
    width: box.width * scale,
    height: box.height * scale,
  );
}

/// A rectangle with corners rounded by [radius], at height [y].
PinboardAcross _roundedAt(Rect box, double y, double radius) {
  final r = math.min(radius, math.min(box.width, box.height) / 2);
  // How far into a rounded corner, above or below.
  final off = math.max(0, math.max(box.top + r - y, y - (box.bottom - r)));
  final inset = r - math.sqrt(math.max(0, r * r - off * off));
  return (left: box.left + inset, right: box.right - inset);
}
