import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/features/wiki/view/pinboard/pinboard_lines.dart';

/// **A dashed connection is drawn in one go, and only where it can be seen** — a
/// long one had hundreds of dashes, each worked out and drawn on its own whenever
/// the map was zoomed.
void main() {
  test('a long dashed line is drawn at once, near what is in view', () {
    final canvas = _Recording();
    const view = Rect.fromLTWH(900, -100, 200, 200);

    paintPinboardLine(
      canvas,
      start: .zero,
      control: const Offset(2500, 0),
      end: const Offset(5000, 0),
      paint: Paint()
        ..style = .stroke
        ..strokeWidth = 2,
      style: (line: PinboardLines.dashed, arrows: null),
      minHead: 10,
      cull: view,
    );

    final [dashes] = canvas.paths;
    final drawn = dashes.getBounds();
    expect(drawn.width, greaterThan(0));
    // Within the view and a dash beyond it on either side.
    expect(drawn.left, greaterThan(view.left - 40));
    expect(drawn.right, lessThan(view.right + 40));
  });

  test('without a view, the whole line is dashed', () {
    final canvas = _Recording();

    paintPinboardLine(
      canvas,
      start: .zero,
      control: const Offset(500, 0),
      end: const Offset(1000, 0),
      paint: Paint()
        ..style = .stroke
        ..strokeWidth = 2,
      style: (line: PinboardLines.dotted, arrows: null),
      minHead: 10,
    );

    final [dots] = canvas.paths;
    expect(dots.getBounds().left, lessThan(5));
    expect(dots.getBounds().right, greaterThan(995));
  });
}

/// Keeps the paths drawn on it.
class _Recording implements Canvas {
  final paths = <Path>[];

  @override
  void drawPath(Path path, Paint paint) => paths.add(path);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
