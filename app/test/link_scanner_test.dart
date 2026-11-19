import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/link_index.dart';
import 'package:hiwiski/components/links/view/link_chip.dart';
import 'package:hiwiski/components/links/view/linked_markdown.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/links/link_index.dart';
import 'package:hiwiski/domain/links/link_text.dart';

/// A line of `[` froze every reader of a shared page: the link pattern scanned from each
/// bracket to the end of the line.
// A generous bound: the tests run as debug JIT, on shared CI runners too. The bugs they
// guard against took 14 and 30 seconds; five seconds still catches them without
// turning red on a slow runner.
const _budget = Duration(seconds: 5);

void main() {
  const id = '01932b3c-4d5e-7f80-8a1b-2c3d4e5f6071';
  const link = '[Router](hiwiski://wiki_page/$id)';
  final brackets = '[' * 200000;

  test('the scanner finds exactly what the pattern finds', () {
    // Short random texts over the characters that matter, each compared with
    // `allMatches` of the pattern itself.
    const pieces = [
      '[',
      ']',
      r'\',
      '\n',
      '(',
      ')',
      'a',
      ' ',
      '#TD-1',
      'hiwiski://todo/$id',
      '](hiwiski://wiki_page/$id)',
      link,
    ];
    final random = Random(7);
    for (int round = 0; round < 20000; round++) {
      final text = [
        for (var i = random.nextInt(12); i >= 0; i--)
          pieces[random.nextInt(pieces.length)],
      ].join();
      final expected = [
        for (final match in linkPattern.allMatches(text))
          '${match.start}:${match.end}',
      ];
      final actual = [
        for (final match in LinkScanner().allMatches(text))
          '${match.start}:${match.end}',
      ];
      expect(actual, equals(expected), reason: text);
    }
  });

  test('a line of brackets is read in linear time', () {
    final text = '$brackets\n$link #TD-1';
    final watch = Stopwatch()..start();

    final references = parseReferences(text);
    final parts = splitReferences(text);

    expect(watch.elapsed, lessThan(_budget));
    expect(
      references.map((reference) => reference.normalized),
      equals(['uri:WIKI_PAGE/$id', 'key:TD-1']),
    );
    expect(parts.whereType<ReferencePart>(), hasLength(2));
  });

  testWidgets('a line of brackets renders in linear time', (tester) async {
    final index = LinkIndex.from([
      const .new(itemType: 'WIKI_PAGE', itemId: id, title: 'Router'),
    ]);
    final watch = Stopwatch()..start();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [linkIndexProvider.overrideWithValue(index)],
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
              child: LinkedMarkdown(data: '${'[' * 9000} $link'),
            ),
          ),
        ),
      ),
    );

    expect(watch.elapsed, lessThan(_budget));
    expect(find.byType(LinkChip), findsOneWidget);
  });
}
