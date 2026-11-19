import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_symbols.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/wiki/page_moves.dart';
import 'package:hiwiski/domain/wiki/wiki_models.dart';
import 'package:hiwiski/domain/wiki/wiki_page.dart';
import 'package:hiwiski/features/wiki/area/view/wiki_tree.dart';

/// The page tree as one uses it: opening a page shows what lies below it, and a long
/// press sorts a page among its siblings.
void main() {
  WikiPage page(String id, {String? parent, int position = 0}) => .new(
    id: id,
    ownerId: 'anna',
    version: 1,
    tags: '',
    parentId: parent,
    position: position,
    kind: 'PAGE',
    title: id,
    content: '',
  );

  final pages = [
    page('House', position: 0),
    page('Tech', parent: 'House'),
    page('Garden', position: 1024),
    page('Travel', position: 2048),
  ];

  Future<void> pumpTree(
    WidgetTester tester, {
    String? selectedId,
    void Function(String id, String targetId, DropZone zone)? onDrop,
    Set<String> movable = const {'House', 'Tech', 'Garden', 'Travel'},
    Set<String> expanded = const {},
    ValueChanged<Set<String>>? onExpandedChanged,
  }) async {
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
          body: WikiTree(
            nodes: WikiNode.build(pages),
            groupShared: const {},
            selectedId: selectedId,
            onSelect: (_) {},
            onDrop: onDrop,
            movable: movable,
            expanded: expanded,
            onExpandedChanged: onExpandedChanged ?? (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // Leaving the wiki and coming back — a tap on "Wiki" below — found the tree
  // collapsed again; it now starts from what it held and hands every change back.
  testWidgets('the tree starts as it was left and says when it changes', (
    tester,
  ) async {
    Set<String>? kept;
    await pumpTree(
      tester,
      expanded: const {'House'},
      onExpandedChanged: (expanded) => kept = expanded,
    );
    expect(find.text('Tech'), findsOneWidget);

    await tester.tap(find.byIcon(HiwiskiSymbols.expandMore).first);
    await tester.pump();
    expect(find.text('Tech'), findsNothing);
    expect(kept, isEmpty);
  });

  // "Expand all" and "Collapse all" change the set from outside the tree.
  testWidgets('the tree follows expanded pages set from outside', (
    tester,
  ) async {
    await pumpTree(tester);
    expect(find.text('Tech'), findsNothing);

    await pumpTree(tester, expanded: expandableOf(WikiNode.build(pages)));
    expect(find.text('Tech'), findsOneWidget);

    await pumpTree(tester, expanded: const {});
    expect(find.text('Tech'), findsNothing);
  });

  test('every page with subpages can be expanded, at any depth', () {
    final nested = [...pages, page('Wifi', parent: 'Tech')];
    expect(expandableOf(WikiNode.build(nested)), equals({'House', 'Tech'}));
  });

  testWidgets('a selected page with subpages is expanded', (tester) async {
    await pumpTree(tester);
    expect(find.text('Tech'), findsNothing);

    await pumpTree(tester, selectedId: 'House');

    expect(find.text('Tech'), findsOneWidget);
  });

  /// A long press, then a move in small steps — as a finger does — to [to].
  Future<void> drag(WidgetTester tester, String title, Offset to) async {
    final from = tester.getCenter(find.text(title));
    final gesture = await tester.startGesture(from);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    for (int i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// A point in a row: [share] of the way down it.
  Offset inRow(WidgetTester tester, String title, double share) {
    final row = tester.getRect(
      find.ancestor(of: find.text(title), matching: find.byType(InkWell)).first,
    );
    return Offset(row.center.dx, row.top + row.height * share);
  }

  testWidgets('dropped on the lower third, a page goes after the row', (
    tester,
  ) async {
    (String, String, DropZone)? dropped;
    await pumpTree(
      tester,
      onDrop: (id, target, zone) => dropped = (id, target, zone),
    );

    await drag(tester, 'House', inRow(tester, 'Garden', 0.85));

    expect(dropped, equals(('House', 'Garden', DropZone.after)));
  });

  testWidgets('dropped on the middle, a page goes inside the row', (
    tester,
  ) async {
    (String, String, DropZone)? dropped;
    await pumpTree(
      tester,
      onDrop: (id, target, zone) => dropped = (id, target, zone),
    );

    await drag(tester, 'Travel', inRow(tester, 'Garden', 0.5));

    expect(dropped, equals(('Travel', 'Garden', DropZone.inside)));
    // The target opens, so the result shows at once — House is collapsed and opens
    // the same way when something is dropped into it.
    await drag(tester, 'Travel', inRow(tester, 'House', 0.5));
    expect(find.text('Tech'), findsOneWidget);
  });

  testWidgets('dropped on the upper third, a page goes before the row', (
    tester,
  ) async {
    (String, String, DropZone)? dropped;
    await pumpTree(
      tester,
      onDrop: (id, target, zone) => dropped = (id, target, zone),
    );

    await drag(tester, 'Travel', inRow(tester, 'House', 0.1));

    expect(dropped, equals(('Travel', 'House', DropZone.before)));
  });

  testWidgets('a page the member may not write does not move', (tester) async {
    (String, String, DropZone)? dropped;
    await pumpTree(
      tester,
      movable: const {'Garden'},
      onDrop: (id, target, zone) => dropped = (id, target, zone),
    );

    await drag(tester, 'House', inRow(tester, 'Travel', 0.85));

    expect(dropped, isNull);
  });

  testWidgets('a row says what lies below the page', (tester) async {
    await pumpTree(tester);

    // House has Tech below it; Garden and Travel have nothing.
    expect(find.text('1 subpage'), findsOneWidget);
    expect(find.textContaining('subpages'), findsNothing);
  });
}
