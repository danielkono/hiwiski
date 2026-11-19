import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/components/links/view/reference_autocomplete.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/links/link_index.dart';
import 'package:hiwiski/app/link_index.dart';

/// The suggestions for `#…`: a choice must land in the text — by tap and by keyboard.
void main() {
  final index = LinkIndex.from(const [
    LinkItem(
      itemType: 'TODO',
      itemId: 't1',
      title: 'Router tauschen',
      entityKey: 'TD-14',
    ),
    LinkItem(
      itemType: 'TODO',
      itemId: 't2',
      title: 'Rasen mähen',
      entityKey: 'TD-15',
    ),
  ]);

  Future<(TextEditingController, FocusNode)> pump(
    WidgetTester tester, {
    Alignment alignment = .topLeft,
  }) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [linkIndexProvider.overrideWithValue(index)],
        child: MaterialApp(
          theme: HiwiskiTheme.light(),
          home: Scaffold(
            body: Padding(
              padding: const .all(16),
              child: Align(
                alignment: alignment,
                child: ReferenceAutocomplete(
                  controller: controller,
                  focusNode: focus,
                  child: TextField(
                    controller: controller,
                    focusNode: focus,
                    maxLines: null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return (controller, focus);
  }

  testWidgets('a tap on a suggestion completes the text', (tester) async {
    final (controller, _) = await pump(tester);
    await tester.enterText(find.byType(TextField), 'siehe #rou');
    await tester.pumpAndSettle();

    expect(find.text('Router tauschen'), findsOneWidget);
    await tester.tap(find.text('Router tauschen'));
    await tester.pumpAndSettle();

    expect(controller.text, equals('siehe #TD-14 '));
    expect(find.text('Router tauschen'), findsNothing);
  });

  testWidgets('Enter takes the highlighted suggestion instead of a new line', (
    tester,
  ) async {
    final (controller, _) = await pump(tester);
    await tester.enterText(find.byType(TextField), 'erst #TD');
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Newest first: TD-15, then TD-14.
    expect(controller.text, equals('erst #TD-14 '));
  });

  testWidgets('the list opens under the line being typed', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'eins\nzwei\ndrei\n#rou');
    await tester.pumpAndSettle();

    final field = tester.getRect(find.byType(TextField));
    final option = tester.getRect(find.text('Router tauschen'));
    expect(option.top, greaterThan(field.top + 3 * 16));
  });

  testWidgets('with no room below the line, the list opens above it', (
    tester,
  ) async {
    await pump(tester, alignment: .bottomLeft);
    await tester.enterText(find.byType(TextField), 'siehe #rou');
    await tester.pumpAndSettle();

    final field = tester.getRect(find.byType(TextField));
    final option = tester.getRect(find.text('Router tauschen'));
    expect(option.bottom, lessThan(field.bottom));
  });

  testWidgets('with a keyboard on the screen the list docks on top of it', (
    tester,
  ) async {
    // Tests run as Android: a keyboard on the screen. 600 high, 300 of them keyboard.
    tester.view.viewInsets = FakeViewPadding(
      bottom: 300 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.reset);
    final (controller, _) = await pump(tester);
    await tester.enterText(find.byType(TextField), 'erst #TD');
    await tester.pumpAndSettle();

    final list = tester.getRect(find.byType(ListView));
    expect(list.bottom, equals(300));
    expect(list.width, equals(800));
    // The best match (newest first: TD-15) sits nearest the keyboard.
    expect(
      tester.getRect(find.text('Rasen mähen')).top,
      greaterThan(tester.getRect(find.text('Router tauschen')).top),
    );

    // Up on the screen is up: from the bottom row to the one above it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.text, equals('erst #TD-14 '));
  });
}
