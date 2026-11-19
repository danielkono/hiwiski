import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/link_index.dart';
import 'package:hiwiski/components/links/view/linked_markdown.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/links/link_index.dart';
import 'package:hiwiski/domain/wiki/markdown_limits.dart';

/// The markdown package's inline parser is quadratic in some inputs: 160 KB of `[a](`
/// took 17 s to render, 80 KB of `*a` 10 s.
void main() {
  Widget page(String data) => ProviderScope(
    overrides: [linkIndexProvider.overrideWithValue(LinkIndex.from(const []))],
    child: MaterialApp(
      theme: HiwiskiTheme.light(),
      localizationsDelegates: const [
        L.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: L.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(child: LinkedMarkdown(data: data)),
      ),
    ),
  );

  for (final (name, data) in [
    ('links that never close', '[a](' * 40000),
    ('emphasis that never closes', '*a' * 40000),
    ('the same just below the limit', '*a' * (maxMarkdownBlock ~/ 2 - 1)),
  ]) {
    testWidgets('$name render in a few seconds at most', (tester) async {
      final watch = Stopwatch()..start();

      await tester.pumpWidget(page(data));

      // A generous bound: the regression took 10 to 17 s.
      expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
      expect(tester.takeException(), isNull);
    });
  }

  test('an oversized paragraph is not Markdown, a long list still is', () {
    expect(renderableAsMarkdown('[a](' * 40000), isFalse);
    expect(renderableAsMarkdown('*a\n' * 20000), isFalse);
    expect(renderableAsMarkdown('> [a](\n' * 10000), isFalse);
    expect(renderableAsMarkdown('- [ ] Zahnbürste einpacken\n' * 2000), isTrue);
    expect(renderableAsMarkdown('Absatz.\n\n' * 5000), isTrue);
    expect(
      renderableAsMarkdown('```\n${'code line\n' * 5000}```\nDanach.'),
      isTrue,
    );
  });

  testWidgets('an oversized text is shown as plain text', (tester) async {
    await tester.pumpWidget(page('**fett** ${'[a](' * 5000}'));

    expect(find.textContaining('**fett**', findRichText: true), findsOneWidget);
  });
}
