import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/core/ui/filter_pill.dart';
import 'package:hiwiski/core/ui/tag_filter_bar.dart';
import 'package:hiwiski/domain/tags/tag.dart';

/// **A selected tag behind "+N" still shows** — on a narrow screen the filter would
/// otherwise look off while it hides most of the list (filter bar).
void main() {
  final tags = [
    for (var i = 0; i < 12; i++)
      Tag(
        id: 'tag-$i',
        ownerId: 'me',
        version: 1,
        name: 'A rather long tag $i',
        colorToken: 'BLUE',
      ),
  ];

  Future<void> pumpBar(
    WidgetTester tester,
    double width, {
    Set<String> selected = const {},
    List<Tag>? only,
  }) async {
    tester.view.physicalSize = Size(width, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: HiwiskiTheme.light(),
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: TagFilterBar(
            tags: only ?? tags,
            selected: selected,
            onToggle: (_) {},
            onClear: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  FilterPill more(WidgetTester tester) => tester.widget<FilterPill>(
    find.byWidgetPredicate(
      (widget) => widget is FilterPill && widget.label.startsWith('+'),
    ),
  );

  testWidgets('"+N" is plain while nothing behind it is selected', (
    tester,
  ) async {
    await pumpBar(tester, 360);
    expect(more(tester).selected, isFalse);
  });

  testWidgets('"+N" is marked when a selected tag does not fit', (
    tester,
  ) async {
    await pumpBar(tester, 200, selected: {'tag-3', 'tag-7'});

    expect(find.text('A rather long tag 7'), findsNothing);
    expect(more(tester).selected, isTrue);
  });

  testWidgets('the pills never run over the end of the row, at any width', (
    tester,
  ) async {
    // The row works out ahead how many pills fit. Short by the outline of each
    // unselected pill, it ran over its end once more than eight short tags were
    // shown (the wiki on an iPad upright): the room kept for "+N" hid it until then.
    final short = [
      for (var i = 0; i < 30; i++)
        Tag(
          id: 'short-$i',
          ownerId: 'me',
          version: 1,
          name: 'T$i',
          colorToken: 'BLUE',
        ),
    ];
    for (double width = 600; width <= 1100; width += 1) {
      await pumpBar(tester, width, only: short);
      expect(tester.takeException(), isNull, reason: 'at $width');
    }
  });
}
