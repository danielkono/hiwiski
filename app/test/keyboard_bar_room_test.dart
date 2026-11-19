import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/ui/keyboard_bar_room.dart';

void main() {
  Future<double> insetWith(
    WidgetTester tester, {
    required double keyboard,
    required double overlap,
  }) async {
    late double inset;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(viewInsets: .only(bottom: keyboard)),
        child: KeyboardBarRoom(
          overlap: overlap,
          child: Builder(
            builder: (context) {
              inset = MediaQuery.viewInsetsOf(context).bottom;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return inset;
  }

  testWidgets('the bar over an open keyboard counts as keyboard', (
    tester,
  ) async {
    expect(await insetWith(tester, keyboard: 230, overlap: 60), equals(290));
  });

  testWidgets('without a keyboard no room is left', (tester) async {
    expect(await insetWith(tester, keyboard: 0, overlap: 60), equals(0));
  });

  testWidgets('without a bar the keyboard stays as it is', (tester) async {
    expect(await insetWith(tester, keyboard: 230, overlap: 0), equals(230));
  });
}
