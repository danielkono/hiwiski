import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/link_index.dart';
import 'package:hiwiski/components/rich_text/view/markdown_field.dart';
import 'package:hiwiski/components/rich_text/view/markdown_text_controller.dart';
import 'package:hiwiski/components/rich_text/view/markdown_toolbar.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_symbols.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/links/link_index.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **Writing formatted**: the text is drawn as it reads, and stays its Markdown.
void main() {
  const text = '## Packing\n- [ ] milk\n- eggs';

  Future<MarkdownTextController> pump(
    WidgetTester tester, {
    Map<String, Object> settings = const {},
    String initial = text,
  }) async {
    SharedPreferences.setMockInitialValues(settings);
    final local = (await tester.runAsync(LocalSettings.open))!;
    final controller = MarkdownTextController(text: initial);
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        overrides: [
          localSettingsProvider.overrideWithValue(local),
          linkIndexProvider.overrideWithValue(LinkIndex.from(const [])),
        ],
        child: MaterialApp(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: L.localizationsDelegates,
          supportedLocales: L.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Column(
              children: [
                MarkdownToolbar(controller: controller, focusNode: focus),
                MarkdownField(controller: controller, focusNode: focus),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  Finder inField(Finder finder) =>
      find.descendant(of: find.byType(TextField), matching: finder);

  testWidgets('it opens formatted: a box instead of "[ ]"', (tester) async {
    final controller = await pump(tester);
    expect(controller.formatted, isTrue);
    expect(inField(find.byIcon(HiwiskiSymbols.checkBoxOutlineBlank)), findsOne);
  });

  testWidgets('a tap on the box ticks it in the text', (tester) async {
    final controller = await pump(tester);
    await tester.tap(inField(find.byIcon(HiwiskiSymbols.checkBoxOutlineBlank)));
    await tester.pump();
    expect(controller.text, equals('## Packing\n- [x] milk\n- eggs'));
    expect(inField(find.byIcon(HiwiskiSymbols.checkBox)), findsOne);
  });

  testWidgets('switched to Markdown, the source shows; the text is the same', (
    tester,
  ) async {
    final controller = await pump(tester);
    await tester.tap(find.byTooltip('Markdown'));
    await tester.pump();
    expect(controller.formatted, isFalse);
    expect(controller.text, equals(text));
    expect(
      inField(find.byIcon(HiwiskiSymbols.checkBoxOutlineBlank)),
      findsNothing,
    );

    await tester.tap(find.byTooltip('Formatted'));
    await tester.pump();
    expect(controller.formatted, isTrue);
  });

  testWidgets('with the default off it opens as Markdown', (tester) async {
    final controller = await pump(
      tester,
      settings: {'hiwiski.editor.formatted': false},
    );
    expect(controller.formatted, isFalse);
    expect(
      inField(find.byIcon(HiwiskiSymbols.checkBoxOutlineBlank)),
      findsNothing,
    );
  });

  testWidgets('the cursor stays out of a hidden prefix', (tester) async {
    final controller = await pump(tester);
    // The start of the heading's line, as a tap at its left edge puts it.
    controller.selection = const TextSelection.collapsed(offset: 0);
    expect(controller.selection.baseOffset, equals(3));
  });

  testWidgets('Backspace at the start of an item makes it text', (
    tester,
  ) async {
    final controller = await pump(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    // After "- " of "- eggs".
    controller.selection = const TextSelection.collapsed(offset: 24);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(controller.text, equals('## Packing\n- [ ] milk\neggs'));
    expect(controller.selection.baseOffset, equals(22));
  });

  testWidgets('Ctrl+B makes the selection bold, and takes it back', (
    tester,
  ) async {
    final controller = await pump(tester, initial: 'Soup');
    await tester.tap(find.byType(TextField));
    await tester.pump();
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(controller.text, equals('**Soup**'));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(controller.text, equals('Soup'));
  });

  testWidgets('what Backspace took as a whole comes back with Undo', (
    tester,
  ) async {
    final controller = await pump(tester, initial: '- a\n- b');
    await tester.tap(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 600));
    controller.selection = const TextSelection.collapsed(offset: 6);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.text, equals('- a\nb'));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.text, equals('- a\n- b'));
  });
}
