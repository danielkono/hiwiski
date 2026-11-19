import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/components/rich_text/view/markdown_toolbar.dart';
import 'package:hiwiski/components/rich_text/view/rich_text_keys.dart';

/// **A tap on "bold" keeps the cursor in the text.**
///
/// When testing, every button in the bar took the focus: the keyboard closed and the
/// next letter went nowhere.
void main() {
  testWidgets('the bar formats without taking the focus from the text', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Soup');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: HiwiskiTheme.light(),
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Column(
            children: [
              MarkdownToolbar(controller: controller, focusNode: focus),
              TextField(controller: controller, focusNode: focus),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    expect(focus.hasFocus, isTrue);

    await tester.tap(find.byTooltip('Bold'));
    await tester.pump();
    expect(controller.text, equals('**Soup**'));
    expect(focus.hasFocus, isTrue);

    await tester.tap(find.byTooltip('Heading'));
    await tester.pump();
    expect(controller.text, equals('## **Soup**'));
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('while images are added the button turns and waits', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    int taps = 0;
    Future<void> pump({required bool busy}) => tester.pumpWidget(
      MaterialApp(
        theme: HiwiskiTheme.light(),
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: MarkdownToolbar(
            controller: controller,
            onImages: () => taps++,
            imagesBusy: busy,
          ),
        ),
      ),
    );

    await pump(busy: true);
    expect(find.byKey(RichTextKeys.insertImages), findsNothing);
    expect(find.byKey(RichTextKeys.imagesBusy), findsOneWidget);
    expect(find.byTooltip('Adding images …'), findsOneWidget);

    await pump(busy: false);
    await tester.tap(find.byKey(RichTextKeys.insertImages));
    expect(taps, equals(1));
  });
}
