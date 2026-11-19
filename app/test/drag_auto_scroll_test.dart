import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/ui/drag_auto_scroll.dart';

/// **The closer to the edge, the faster** — and nothing away from it.
void main() {
  late ScrollController scroll;
  late BuildContext inside;

  Future<void> pumpList(WidgetTester tester) async {
    scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: .ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: 600,
            child: ListView(
              controller: scroll,
              children: [
                Builder(
                  builder: (context) {
                    inside = context;
                    return const SizedBox(height: 5000);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// How far the list scrolls in half a second with the pointer at [y].
  Future<double> scrolledWithPointerAt(WidgetTester tester, double y) async {
    final scrollBy = DragAutoScroll();
    final before = scroll.offset;
    scrollBy.update(inside, Offset(100, y));
    await tester.pump(const Duration(milliseconds: 500));
    scrollBy.stop();
    return scroll.offset - before;
  }

  testWidgets('nothing in the middle, faster towards the edge', (tester) async {
    await pumpList(tester);

    final middle = await scrolledWithPointerAt(tester, 300);
    final zone = await scrolledWithPointerAt(tester, 560);
    final nearEdge = await scrolledWithPointerAt(tester, 590);
    final atEdge = await scrolledWithPointerAt(tester, 600);

    expect(middle, equals(0));
    expect(zone, greaterThan(0));
    expect(nearEdge, greaterThan(zone * 2));
    expect(atEdge, greaterThan(nearEdge));
  });

  testWidgets('upwards at the top', (tester) async {
    await pumpList(tester);
    scroll.jumpTo(1000);

    expect(await scrolledWithPointerAt(tester, 5), lessThan(0));
  });
}
