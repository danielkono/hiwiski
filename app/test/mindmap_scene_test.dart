import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/wiki/mindmap.dart';
import 'package:hiwiski/features/wiki/view/mindmap/mindmap_scene.dart';

/// The scene draws a turned element as it is seen: built while any of it is in
/// view.
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
}
