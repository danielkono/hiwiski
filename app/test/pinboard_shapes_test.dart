import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/domain/wiki/pinboard.dart';
import 'package:hiwiski/features/wiki/view/pinboard/pinboard_scene.dart';

/// **A note's text stays inside its outline, whatever its shape.** A pill as wide as
/// it is high is a circle, and with the fixed room of a long pill its lines ran out
/// of it; a diamond's ran over its slanted edges.
void main() {
  PinboardNode note(String shape, int width, int height) => .new(
    id: 'n',
    ownerId: 'anna',
    version: 1,
    pageId: 'page',
    kind: PinboardKinds.note,
    x: 0,
    y: 0,
    width: width,
    height: height,
    layer: 1,
    text: 'Text',
    shape: shape,
  );

  /// Whether [point] lies inside [shape] drawn into [box].
  bool inside(String shape, Rect box, Offset point) {
    final c = box.center;
    final a = box.width / 2;
    final b = box.height / 2;
    final dx = (point.dx - c.dx).abs();
    final dy = (point.dy - c.dy).abs();
    switch (shape) {
      case PinboardShapes.ellipse:
        return (dx * dx) / (a * a) + (dy * dy) / (b * b) <= 1;
      case PinboardShapes.diamond:
        return dx / a + dy / b <= 1;
      case PinboardShapes.pill:
        // A rectangle with half circles of the shorter side at both ends.
        final r = math.min(a, b);
        final ex = math.max(0, dx - (a - r));
        final ey = math.max(0, dy - (b - r));
        return ex * ex + ey * ey <= r * r;
      default:
        return box.contains(point);
    }
  }

  for (final shape in [
    PinboardShapes.ellipse,
    PinboardShapes.diamond,
    PinboardShapes.pill,
  ]) {
    for (final (width, height) in [(220, 220), (300, 120), (120, 300)]) {
      test('$shape, $width × $height: the text area is inside', () {
        final box = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
        final text = PinboardElementView.insetOf(note(shape, width, height))
            .deflateRect(box);
        for (final corner in [
          text.topLeft,
          text.topRight,
          text.bottomLeft,
          text.bottomRight,
        ]) {
          expect(inside(shape, box, corner), isTrue, reason: '$corner');
        }
      });
    }
  }
}
