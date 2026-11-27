import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_metrics.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/wiki/mindmap.dart';
import 'package:hiwiski/features/wiki/view/mindmap/mindmap_scene.dart';

/// **A grip never takes the element**: the resize corner is as large to a finger at
/// every zoom, but lies mostly outside its element — zoomed
/// far out, a corner of a finger's size covered the whole element, and a drag meant
/// to move it resized it.
void main() {
  const node = MindmapNode(
    id: 'a',
    ownerId: 'anna',
    version: 1,
    pageId: 'page',
    kind: MindmapKinds.plain,
    x: 0,
    y: 0,
    width: 200,
    height: 100,
    layer: 1,
    text: 'Meer',
  );

  Future<List<String>> touch(WidgetTester tester, double zoom) async {
    final hits = <String>[];
    final map = Mindmap(nodes: const [node], edges: const []);
    final area = MindmapScene.areaOf(map, zoom: zoom);
    await tester.pumpWidget(
      MaterialApp(
        theme: HiwiskiTheme.light(),
        localizationsDelegates: L.localizationsDelegates,
        home: Scaffold(
          body: Center(
            child: Transform.scale(
              scale: zoom,
              child: MindmapScene(
                map: map,
                area: area,
                linkTarget: (_) => null,
                zoom: zoom,
                resizable: node.id,
                element: (_, child) => GestureDetector(
                  behavior: .opaque,
                  onTap: () => hits.add('move'),
                  child: child,
                ),
                resize: (_, corner) => GestureDetector(
                  behavior: .opaque,
                  onTap: () => hits.add('resize'),
                  child: corner,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final scene = tester.getRect(find.byType(MindmapScene));
    // Points of the map on screen, the scene scaled about its centre.
    Offset at(double x, double y) =>
        scene.topLeft + Offset(x - area.left, y - area.top) * zoom;
    for (final point in [
      at(node.width / 2, node.height / 2), // the middle
      at(node.width * 0.6, node.height * 0.6), // towards the corner
      // The corner of the frame, which stands a little off the element.
      at(
        node.width + HiwiskiMetrics.mindmapFrameGap / zoom,
        node.height + HiwiskiMetrics.mindmapFrameGap / zoom,
      ),
    ]) {
      await tester.tapAt(point);
    }
    return hits;
  }

  for (final zoom in [1.0, 0.25, 0.1]) {
    testWidgets('at a zoom of $zoom the middle moves, the corner resizes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final hits = await touch(tester, zoom);

      expect(hits, equals(['move', 'move', 'resize']));
    });
  }

  test('the margin leaves room for the grips of the outermost element', () {
    final map = Mindmap(nodes: const [node], edges: const []);
    final area = MindmapScene.areaOf(map, zoom: 0.1);
    expect(
      area.right - node.width,
      greaterThanOrEqualTo(HiwiskiMetrics.minTapTarget / 0.1),
    );
  });
}
