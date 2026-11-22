import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import 'mindmap_camera.dart';

/// The grid under the map: a dot at each crossing, as far apart as
/// [HiwiskiMetrics.mindmapGrid] in the map's units — or a multiple of it, zoomed out so
/// far that they would crowd into a grey.
///
/// Drawn on the screen, not in the map: only the dots in view, all in one call, and
/// again only when the view moves. Drawn in the map, each dot a circle of its own and
/// a screen's worth around the view as well, it was tens of thousands of circles in
/// every frame, and moving the map stuttered.
class MindmapGrid extends StatelessWidget {
  const MindmapGrid({super.key, required this.camera});

  final MindmapCamera camera;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        painter: _GridPainter(
          camera: camera,
          color: context.scheme.outlineVariant,
        ),
      ),
    ),
  );
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.camera, required this.color})
    : super(repaint: camera);

  final MindmapCamera camera;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = camera.scale;
    if (scale <= 0) return;
    double step = HiwiskiMetrics.mindmapGrid;
    while (step * scale < HiwiskiMetrics.mindmapGridMinGap) {
      step *= 2;
    }
    final origin = camera.origin;
    // The crossings in view, from the first one left of and above it.
    final first = camera.toScene(Offset.zero);
    final last = camera.toScene(Offset(size.width, size.height));
    final left = (first.dx / step).floorToDouble() * step;
    final top = (first.dy / step).floorToDouble() * step;
    final columns = ((last.dx - left) / step).ceil() + 1;
    final rows = ((last.dy - top) / step).ceil() + 1;
    if (columns <= 0 || rows <= 0) return;
    final points = Float32List(columns * rows * 2);
    int at = 0;
    for (int column = 0; column < columns; column++) {
      final x = origin.dx + (left + column * step) * scale;
      for (int row = 0; row < rows; row++) {
        points[at++] = x;
        points[at++] = origin.dy + (top + row * step) * scale;
      }
    }
    canvas.drawRawPoints(
      ui.PointMode.points,
      points,
      Paint()
        ..color = color
        ..strokeCap = .round
        ..strokeWidth = HiwiskiMetrics.mindmapGridDot * 2,
    );
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      oldDelegate.camera != camera || oldDelegate.color != color;
}
