import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../../../domain/wiki/pinboard_shapes.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/ui/flowing_text.dart';

/// The outline of an element's [shape], [pad] inside it all round: what a note's
/// lines fill when they follow its shape. As drawn by `PinboardElementView.shapeOf`:
/// a diamond's corners on the middles of its box's sides, a pill's ends half
/// circles, an unknown shape a rounded rectangle.
class PinboardOutline extends FlowOutline {
  const PinboardOutline(this.shape, {required this.pad});

  final String shape;
  final double pad;

  @override
  FlowChord? chordOf(Size size, double top, double bottom) {
    final geometry = pinboardShapeOf(shape);
    final inner = geometry.inside(Offset.zero & size, pad);
    if (inner.isEmpty || top < inner.top || bottom > inner.bottom) return null;
    // A rounded rectangle's corners, rounded less [pad] inside it.
    final corner = math.max(0.0, HiwiskiMetrics.radiusCard - pad);
    // The outlines are convex: over a band, the room is narrowest at its top or its
    // bottom.
    final upper = geometry.across(inner, top, corner);
    final lower = geometry.across(inner, bottom, corner);
    final left = math.max(upper.left, lower.left);
    final right = math.min(upper.right, lower.right);
    return right > left ? (left: left, right: right) : null;
  }

  @override
  bool operator ==(Object other) =>
      other is PinboardOutline && other.shape == shape && other.pad == pad;

  @override
  int get hashCode => Object.hash(shape, pad);
}
