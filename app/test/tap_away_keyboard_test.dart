import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/ui/tap_away_keyboard.dart';

/// **The keyboard can be closed** — by a tap on empty space, not by a tap on a button.
void main() {
  Future<FocusNode> pump(WidgetTester tester, VoidCallback onPressed) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => TapAwayKeyboard(child: child!),
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: focus, maxLines: null),
              TextButton(onPressed: onPressed, child: const Text('Bold')),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    return focus;
  }

  testWidgets('a tap on empty space closes it', (tester) async {
    final focus = await pump(tester, () {});

    await tester.tapAt(const Offset(400, 500));
    await tester.pump();

    expect(focus.hasFocus, isFalse);
  });

  testWidgets('a tap on a button leaves it open', (tester) async {
    int taps = 0;
    final focus = await pump(tester, () => taps++);

    await tester.tap(find.text('Bold'));
    await tester.pump();

    expect(taps, equals(1));
    expect(focus.hasFocus, isTrue);
  });
}
