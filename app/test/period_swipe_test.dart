import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/ui/period_swipe.dart';

/// **The week and the month turn like a page** — by touch; a mouse drag moves events.
void main() {
  Future<List<int>> swipe(
    WidgetTester tester,
    Offset by, {
    PointerDeviceKind kind = .touch,
  }) async {
    final shifts = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PeriodSwipe(
          onShift: shifts.add,
          child: const SizedBox.expand(key: Key('period')),
        ),
      ),
    );
    await tester.fling(
      find.byKey(const Key('period')),
      by,
      1000,
      deviceKind: kind,
    );
    await tester.pumpAndSettle();
    return shifts;
  }

  testWidgets('to the left is the next period', (tester) async {
    expect(await swipe(tester, const Offset(-200, 0)), equals([1]));
  });

  testWidgets('to the right is the previous period', (tester) async {
    expect(await swipe(tester, const Offset(200, 0)), equals([-1]));
  });

  testWidgets('a mouse drag turns nothing', (tester) async {
    expect(await swipe(tester, const Offset(-200, 0), kind: .mouse), isEmpty);
  });

  testWidgets('a vertical scroll turns nothing', (tester) async {
    expect(await swipe(tester, const Offset(0, -200)), isEmpty);
  });
}
