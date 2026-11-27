import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../../../core/common/wire.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/ui/flowing_text.dart';

/// The outline of an element's [shape], [pad] inside it all round: what a note's
/// lines fill when they follow its shape. As drawn by `MindmapElementView.shapeOf`:
/// a diamond's corners on the middles of its box's sides, a pill's ends half
/// circles, an unknown shape a rounded rectangle.
class MindmapOutline extends FlowOutline {
  const MindmapOutline(this.shape, {required this.pad});

  final String shape;
  final double pad;

  @override
  FlowChord? chordOf(Size size, double top, double bottom) {
    final inner = _innerOf(Offset.zero & size);
    if (inner.isEmpty || top < inner.top || bottom > inner.bottom) return null;
    // The shapes are convex: over a band, the room is narrowest at its top or its
    // bottom.
    final upper = _across(inner, top);
    final lower = _across(inner, bottom);
    final left = math.max(upper.left, lower.left);
    final right = math.min(upper.right, lower.right);
    return right > left ? (left: left, right: right) : null;
  }

  /// The box of the shape [pad] inside the one drawn in [box]. A diamond shrinks
  /// about its middle: [pad] off its slanted sides takes more off its corners.
  Rect _innerOf(Rect box) {
    if (shape != MindmapShapes.diamond) return box.deflate(pad);
    final across = box.width / 2;
    final upDown = box.height / 2;
    if (across <= 0 || upDown <= 0) return .zero;
    final slant = math.sqrt(across * across + upDown * upDown);
    final scale = 1 - pad * slant / (across * upDown);
    if (scale <= 0) return .zero;
    return Rect.fromCenter(
      center: box.center,
      width: box.width * scale,
      height: box.height * scale,
    );
  }

  /// The room across the shape drawn in [box] has at height [y].
  FlowChord _across(Rect box, double y) {
    final middle = box.center;
    switch (shape) {
      case MindmapShapes.rectangle:
        return (left: box.left, right: box.right);
      case MindmapShapes.ellipse:
        final off = (y - middle.dy) / (box.height / 2);
        final half = box.width / 2 * math.sqrt(math.max(0, 1 - off * off));
        return (left: middle.dx - half, right: middle.dx + half);
      case MindmapShapes.diamond:
        final off = (y - middle.dy).abs() / (box.height / 2);
        final half = box.width / 2 * math.max(0, 1 - off);
        return (left: middle.dx - half, right: middle.dx + half);
      case MindmapShapes.pill:
        return _rounded(box, y, math.min(box.width, box.height) / 2);
      default:
        return _rounded(box, y, math.max(0, HiwiskiMetrics.radiusCard - pad));
    }
  }

  /// A rectangle with corners rounded by [radius], at height [y].
  static FlowChord _rounded(Rect box, double y, double radius) {
    final r = math.min(radius, math.min(box.width, box.height) / 2);
    // How far into a rounded corner, above or below.
    final off = math.max(0, math.max(box.top + r - y, y - (box.bottom - r)));
    final inset = r - math.sqrt(math.max(0, r * r - off * off));
    return (left: box.left + inset, right: box.right - inset);
  }

  @override
  bool operator ==(Object other) =>
      other is MindmapOutline && other.shape == shape && other.pad == pad;

  @override
  int get hashCode => Object.hash(shape, pad);
}
