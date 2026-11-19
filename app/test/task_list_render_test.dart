import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/link_index.dart';
import 'package:hiwiski/components/links/view/linked_markdown.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/links/link_index.dart';
import 'package:hiwiski/domain/wiki/markdown_editing.dart';

/// The boxes of a nested task list: which one a tap ticks, and which ones are drawn.
void main() {
  Future<List<int>> tapAll(WidgetTester tester, String data) async {
    final ticked = <int>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          linkIndexProvider.overrideWithValue(LinkIndex.from(const [])),
        ],
        child: MaterialApp(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: const [
            L.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: L.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: LinkedMarkdown(data: data, onToggleTask: ticked.add),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boxes = find.byType(InkWell);
    final count = boxes.evaluate().length;
    for (int i = 0; i < count; i++) {
      await tester.tap(boxes.at(i));
    }
    return ticked;
  }

  testWidgets('a tap ticks the box it is on, however deeply nested', (
    tester,
  ) async {
    // Top to bottom: a, b, c, d — the document order the text is edited in.
    final ticked = await tapAll(
      tester,
      '- [ ] a\n  - [ ] b\n    - [ ] c\n- [ ] d\n',
    );
    expect(ticked, equals([0, 1, 2, 3]));
  });

  testWidgets('a list with a blank line in it has a box on every level', (
    tester,
  ) async {
    final ticked = await tapAll(tester, '- [ ] a\n\n  - [ ] b\n- [ ] c\n');
    expect(ticked, equals([0, 1, 2]));
  });

  test('the render order puts children before their parent', () {
    expect(
      taskRenderOrder('- [ ] a\n  - [ ] b\n    - [ ] c\n- [ ] d\n'),
      equals([2, 1, 0, 3]),
    );
    expect(taskRenderOrder('- [ ] a\n- [ ] b\n'), equals([0, 1]));
    expect(taskRenderOrder('no boxes'), isEmpty);
  });
}
