import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/ui/drag_auto_scroll.dart';
import 'package:hiwiski/core/ui/item_draggable.dart';

/// **A held row survives being scrolled out of sight.** Flutter's `Draggable` reports
/// moves and the end of a drag only while its widget is mounted; a list that scrolled
/// the held row away threw the widget out — the list stopped scrolling, and the drag
/// never ended.
///
/// **By touch a long press alone lifts nothing.** Only once the held finger moves is
/// the row picked up — held to edit a title, nothing flickers.
void main() {
  testWidgets('held without moving nothing is lifted; moving on lifts it', (
    tester,
  ) async {
    int started = 0;
    int ended = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ItemDraggable<int>(
                data: 0,
                feedback: const SizedBox(width: 100, height: 40),
                childWhenDragging: const Text('held'),
                onDragStarted: () => started++,
                onDragUpdate: (_) {},
                onDragDone: () => ended++,
                child: const SizedBox(height: 60, child: Text('row')),
              ),
            ],
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('row')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await tester.pump();
    expect(started, equals(0));
    expect(find.text('held'), findsNothing);

    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(started, equals(1));
    expect(find.text('held'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(ended, greaterThan(0));
  });

  testWidgets('the list keeps scrolling, and the drag ends, after the held row '
      'left the screen', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final autoScroll = DragAutoScroll();
    addTearDown(autoScroll.stop);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    int ended = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            controller: controller,
            itemCount: 50,
            itemExtent: 60,
            itemBuilder: (context, index) => ItemDraggable<int>(
              data: index,
              feedback: const SizedBox(width: 100, height: 40),
              childWhenDragging: Text('held $index'),
              onDragStarted: () {},
              onDragUpdate: (details) =>
                  autoScroll.update(context, details.globalPosition),
              onDragDone: () {
                ended++;
                autoScroll.stop();
              },
              child: Text('row $index'),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('row 0')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    // Down to the bottom edge, held there: the list scrolls on its own.
    for (int i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset(200, 30 + 560 * i / 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    for (int i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Row 0 is far out of sight by now.
    final scrolled = controller.offset;
    expect(scrolled, greaterThan(600));

    // A move after that still arrives: back up to the top edge scrolls back.
    for (int i = 1; i <= 5; i++) {
      await gesture.moveTo(Offset(200, 590 - 580 * i / 5));
      await tester.pump(const Duration(milliseconds: 16));
    }
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.offset, lessThan(scrolled));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(ended, greaterThan(0));
  });
}
