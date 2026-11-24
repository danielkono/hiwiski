import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/common/change.dart';
import 'package:hiwiski/domain/wiki/mindmap.dart';
import 'package:hiwiski/features/wiki/view/mindmap/mindmap_scene.dart';

/// The scene draws a turned element as it is seen: built while any of it is in
/// view, and this device's version of it in a conflict turned as it wrote it.
void main() {
  Future<void> show(
    WidgetTester tester,
    Mindmap map, {
    Rect? visible,
    MindmapNode? mine,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: HiwiskiTheme.light(),
      localizationsDelegates: L.localizationsDelegates,
      home: Scaffold(
        body: SingleChildScrollView(
          scrollDirection: .horizontal,
          child: SingleChildScrollView(
            child: MindmapScene(
              map: map,
              area: MindmapScene.areaOf(map),
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
    final map = Mindmap(
      nodes: const [
        MindmapNode(
          id: 'bar',
          ownerId: 'anna',
          version: 1,
          pageId: 'page',
          kind: MindmapKinds.plain,
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
    const theirs = MindmapNode(
      id: 'a',
      ownerId: 'anna',
      version: 1,
      pageId: 'page',
      kind: MindmapKinds.plain,
      x: 0,
      y: 0,
      width: 100,
      height: 50,
      layer: 1,
      text: 'Meer',
    );
    final map = Mindmap(nodes: const [theirs], edges: const []);
    // Only its turn lost: it stands beside the map's, turned upright.
    final mine = theirs.styled(rotation: const Change(90));

    await show(tester, map, mine: mine);

    final scene = tester.getTopLeft(find.byType(MindmapScene));
    final area = MindmapScene.areaOf(map);
    final ghost = find.descendant(
      of: find.byKey(const ValueKey('mindmap-mine')),
      matching: find.byType(MindmapElementView),
    );
    // Upright, 50 wide, its left edge a gap of 24 right of the map's version (at
    // 100): its middle at (149, 25), its own top left corner turned to (174, -25).
    final corner = tester.getTopLeft(ghost) - scene + area.topLeft;
    expect(corner.dx, moreOrLessEquals(174, epsilon: 0.01));
    expect(corner.dy, moreOrLessEquals(-25, epsilon: 0.01));
  });
}
