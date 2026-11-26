import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/core/theme/pinboard_colors.dart';
import 'package:hiwiski/domain/wiki/pinboard.dart';
import 'package:hiwiski/features/wiki/view/pinboard/pinboard_scene.dart';

/// The scene draws an element as it is seen: a turned one built while any of it is
/// in view, this device's version of it in a conflict turned as it wrote it, and a
/// text coloured to read on what shows through a see-through surface.
void main() {
  Future<void> show(
    WidgetTester tester,
    Pinboard map, {
    Rect? visible,
    PinboardNode? mine,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: HiwiskiTheme.light(),
      localizationsDelegates: L.localizationsDelegates,
      home: Scaffold(
        body: SingleChildScrollView(
          scrollDirection: .horizontal,
          child: SingleChildScrollView(
            child: PinboardScene(
              map: map,
              area: PinboardScene.areaOf(map),
              linkTarget: (_) => null,
              visible: visible,
              mine: mine,
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('a turned element is built while what is seen of it is in view', (
    tester,
  ) async {
    // A long bar turned upright about its middle (500, 10): seen from y -490 to 510.
    final map = Pinboard(
      nodes: [
        PinboardNode(
          id: 'bar',
          ownerId: 'anna',
          version: 1,
          pageId: 'page',
          kind: PinboardKinds.plain,
          x: 0,
          y: 0,
          width: 1000,
          height: 20,
          layer: 1,
          text: 'Bar',
          rotation: 90,
        ),
      ],
      edges: const [],
    );

    // A view on its lower end, far below where it lay before it was turned.
    await show(tester, map, visible: const Rect.fromLTWH(480, 400, 40, 40));

    expect(find.byKey(const ValueKey('bar')), findsOneWidget);
  });

  testWidgets('this device\'s version of an element is drawn turned as it is', (
    tester,
  ) async {
    final theirs = PinboardNode(
      id: 'a',
      ownerId: 'anna',
      version: 1,
      pageId: 'page',
      kind: PinboardKinds.plain,
      x: 0,
      y: 0,
      width: 100,
      height: 50,
      layer: 1,
      text: 'Meer',
    );
    final map = Pinboard(nodes: [theirs], edges: const []);
    // Only its turn lost: it stands beside the map's, turned upright.
    final mine = theirs.withFields({WireFields.rotation: 90});

    await show(tester, map, mine: mine);

    final scene = tester.getTopLeft(find.byType(PinboardScene));
    final area = PinboardScene.areaOf(map);
    final ghost = find.descendant(
      of: find.byKey(const ValueKey('pinboard-mine')),
      matching: find.byType(PinboardElementView),
    );
    // Upright, 50 wide, its left edge a gap of 24 right of the map's version (at
    // 100): its middle at (149, 25), its own top left corner turned to (174, -25).
    final corner = tester.getTopLeft(ghost) - scene + area.topLeft;
    expect(corner.dx, moreOrLessEquals(174, epsilon: 0.01));
    expect(corner.dy, moreOrLessEquals(-25, epsilon: 0.01));
  });

  testWidgets('a text colour on a see-through surface reads on what is seen', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: HiwiskiTheme.light(),
        home: Builder(
          builder: (built) {
            context = built;
            return const SizedBox();
          },
        ),
      ),
    );
    // Black, nearly see-through: over the light canvas, a pale grey is seen.
    final fill = PinboardPaint.of(context, '#00000010').fill;
    final seen = Color.alphaBlend(fill, Theme.of(context).colorScheme.surface);

    // White text: measured on black it read; on the pale grey it would not.
    final ink = PinboardPaint.textOf(context, '#FFFFFF', fill)!;
    expect(PinboardPaint.contrast(ink, seen), greaterThanOrEqualTo(4.5));
  });
}
