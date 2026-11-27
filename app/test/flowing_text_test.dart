import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/ui/flowing_text.dart';
import 'package:hiwiski/features/wiki/view/mindmap/mindmap_outline.dart';

/// **Text fills its outline line by line**: in a box every line is as wide as the
/// box; in a circle or a diamond each line as wide as the shape is at its height,
/// and none crosses its outline. A word moves down to where it fits whole, unless
/// no line is wide enough for it; what does not fit at all is cut at the end.
void main() {
  const style = TextStyle(fontSize: 10);
  const words =
      'Zelt Kocher Schlafsack Isomatte Stirnlampe Wasserfilter Karte '
      'Kompass Messer Seil Plane Topf Becher';
  const size = Size(200, 160);

  Future<RenderFlowingText> lay(
    WidgetTester tester,
    String text, {
    FlowOutline outline = const FlowBox(),
    AlignmentGeometry place = AlignmentDirectional.topStart,
    Size size = size,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: .ltr,
        child: Center(
          child: SizedBox.fromSize(
            size: size,
            child: FlowingText(
              paragraphs: [FlowParagraph(TextSpan(text: text, style: style))],
              outline: outline,
              place: place,
            ),
          ),
        ),
      ),
    );
    return tester.renderObject(find.byType(FlowingText));
  }

  String shown(RenderFlowingText text) =>
      text.lines.map((line) => line.text).join(' ');

  testWidgets('a short line stands where it is placed, in a box', (
    tester,
  ) async {
    for (final (place, x, y) in [
      (AlignmentDirectional.topStart, 0.0, 0.0),
      (AlignmentDirectional.center, 0.5, 0.5),
      (AlignmentDirectional.bottomEnd, 1.0, 1.0),
    ]) {
      final text = await lay(tester, 'Zelt', place: place);
      final line = text.lines.single.rect;
      expect(line.width, equals(40), reason: '$place');
      expect(line.left, closeTo((size.width - line.width) * x, 0.5));
      expect(line.top, closeTo((size.height - line.height) * y, 0.5));
    }
  });

  testWidgets('lines in an ellipse stay inside it, short at its top', (
    tester,
  ) async {
    final text = await lay(
      tester,
      words,
      outline: const MindmapOutline(MindmapShapes.ellipse, pad: 8),
      place: AlignmentDirectional.center,
    );
    expect(shown(text), equals(words));
    bool inside(Offset point) {
      final across = (point.dx - size.width / 2) / (size.width / 2);
      final upDown = (point.dy - size.height / 2) / (size.height / 2);
      return across * across + upDown * upDown <= 1;
    }

    for (final line in text.lines) {
      final rect = line.rect.deflate(0.5);
      for (final corner in [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
      ]) {
        expect(inside(corner), isTrue, reason: '${line.text} at $corner');
      }
    }
    final widths = [for (final line in text.lines) line.rect.width];
    expect(widths.first, lessThan(widths.reduce(math.max)));
    expect(widths.last, lessThan(widths.reduce(math.max)));
    // Each line in the middle of its own room.
    for (final line in text.lines) {
      expect(line.rect.center.dx, closeTo(size.width / 2, 0.5));
    }
  });

  testWidgets('lines in a diamond narrow towards its corners', (tester) async {
    const diamond = Size(280, 220);
    final text = await lay(
      tester,
      words,
      outline: const MindmapOutline(MindmapShapes.diamond, pad: 8),
      place: AlignmentDirectional.topCenter,
      size: diamond,
    );
    expect(shown(text), equals(words));
    for (final line in text.lines) {
      final rect = line.rect.deflate(0.5);
      for (final corner in [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
      ]) {
        final across =
            (corner.dx - diamond.width / 2).abs() / (diamond.width / 2);
        final upDown =
            (corner.dy - diamond.height / 2).abs() / (diamond.height / 2);
        expect(across + upDown, lessThanOrEqualTo(1), reason: line.text);
      }
    }
    // A point at the top: the first line holds one word, the widest many.
    expect(text.lines.first.text, equals('Zelt'));
    expect(
      text.lines.map((line) => line.rect.width).reduce(math.max),
      greaterThan(text.lines.first.rect.width * 2),
    );
  });

  testWidgets('a text too long for a diamond ends at a whole word', (
    tester,
  ) async {
    final text = await lay(
      tester,
      words,
      outline: const MindmapOutline(MindmapShapes.diamond, pad: 8),
      place: AlignmentDirectional.topCenter,
    );
    expect(shown(text), isNot(words));
    expect(words.split(' '), containsAll(shown(text).split(' ')));
  });

  testWidgets(
    'a word too long for any line is broken, and what follows shows',
    (tester) async {
      const long = 'Donaudampfschifffahrtsgesellschaftskapitän';
      final text = await lay(
        tester,
        '$long Ende',
        outline: const MindmapOutline(MindmapShapes.ellipse, pad: 8),
      );
      expect(text.lines.map((line) => line.text).join(), contains(long));
      expect(text.lines.last.text, endsWith('Ende'));
    },
  );

  testWidgets('a text too tall for its box starts at its top', (tester) async {
    final text = await lay(
      tester,
      words,
      size: const Size(100, 30),
      place: AlignmentDirectional.bottomCenter,
    );
    expect(text.lines.first.rect.top, equals(0));
    expect(shown(text), isNot(words));
  });

  testWidgets('a widget stands in its line, and the line where it is placed', (
    tester,
  ) async {
    const chip = Key('chip');
    await tester.pumpWidget(
      Directionality(
        textDirection: .ltr,
        child: Center(
          child: SizedBox.fromSize(
            size: size,
            child: FlowingText(
              paragraphs: [
                const FlowParagraph(
                  TextSpan(
                    style: style,
                    children: [
                      TextSpan(text: 'Vor '),
                      WidgetSpan(
                        child: SizedBox(key: chip, width: 30, height: 10),
                      ),
                      TextSpan(text: ' nach'),
                    ],
                  ),
                ),
              ],
              place: AlignmentDirectional.center,
            ),
          ),
        ),
      ),
    );
    final text = tester.renderObject<RenderFlowingText>(
      find.byType(FlowingText),
    );
    final box = tester.getRect(find.byType(FlowingText));
    final line = text.lines.single.rect.shift(box.topLeft);
    final widget = tester.getRect(find.byKey(chip));
    expect(line.center.dx, closeTo(box.center.dx, 0.5));
    expect(widget.left, greaterThan(line.left));
    expect(widget.right, lessThan(line.right));
    expect(widget.top, greaterThanOrEqualTo(line.top - 0.5));
    expect(widget.bottom, lessThanOrEqualTo(line.bottom + 0.5));
  });
}
