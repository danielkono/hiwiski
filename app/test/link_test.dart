import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/link_index.dart';
import 'package:hiwiski/components/links/view/link_chip.dart';
import 'package:hiwiski/components/links/view/linked_markdown.dart';
import 'package:hiwiski/components/links/view/linked_text.dart';
import 'package:hiwiski/components/links/view/references_section.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_metrics.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/core/ui/info_bar.dart';
import 'package:hiwiski/core/ui/ui_keys.dart';
import 'package:hiwiski/domain/common/item_ref.dart';
import 'package:hiwiski/domain/links/link_index.dart';
import 'package:hiwiski/domain/links/link_text.dart';

/// References on the device: **derived, not queried.**
///
/// The server writes its `link` table from the same text; this checks what the app makes
/// of it — both directions, the current title, and the disappearance of whatever is not
/// on this device.
void main() {
  LinkItem page(String id, String title, {String? key, String? text}) => .new(
    itemType: 'WIKI_PAGE',
    itemId: id,
    title: title,
    entityKey: key,
    text: text,
  );

  LinkItem todo(String id, String title, {String? key, String? text}) => .new(
    itemType: 'TODO',
    itemId: id,
    title: title,
    entityKey: key,
    text: text,
    containerId: 'list-1',
  );

  group('the references kept across rebuilds', () {
    test('an edited text is read again, the others are not', () {
      final cache = ReferenceCache();
      final router = todo('t1', 'Router', key: 'TD-1');
      final printer = todo('t2', 'Drucker', key: 'TD-2');
      LinkIndex.from([
        page('p1', 'Internet', text: 'Siehe #TD-1.'),
        router,
        printer,
      ], references: cache);

      // The page now points elsewhere: the index follows the new text.
      final index = LinkIndex.from([
        page('p1', 'Internet', text: 'Siehe #TD-2.'),
        router,
        printer,
      ], references: cache);
      expect(
        index.outgoing('WIKI_PAGE', 'p1').map((i) => i.itemId),
        equals(['t2']),
      );
      expect(index.incoming('TODO', 't1'), isEmpty);
    });

    test('a text that is gone is forgotten', () {
      final cache = ReferenceCache();
      LinkIndex.from([
        page('p1', 'A', text: 'Siehe #TD-1.'),
      ], references: cache);
      final first = cache.of('Siehe #TD-1.');
      LinkIndex.from([page('p1', 'A', text: 'Anders.')], references: cache);
      LinkIndex.from([page('p1', 'A', text: 'Anders.')], references: cache);
      // Parsed anew: an equal list, but not the one kept before.
      expect(cache.of('Siehe #TD-1.'), isNot(same(first)));
    });
  });

  group('the derivation', () {
    test('the typed number yields both directions', () {
      final index = LinkIndex.from([
        page('p1', 'Internet', text: 'Zugangsdaten stehen in #WIKI-3.'),
        page('p2', 'Router', key: 'WIKI-3'),
      ]);

      expect(index.outgoing('WIKI_PAGE', 'p1').single.itemId, equals('p2'));
      // "Links here" comes from the same derivation -- that is why it is there offline.
      expect(index.incoming('WIKI_PAGE', 'p2').single.itemId, equals('p1'));
    });

    test('the address from the picker yields the same', () {
      const id = '01932b3c-4d5e-7f80-8a1b-2c3d4e5f6071';
      final index = LinkIndex.from([
        page('p1', 'Internet', text: '[Router](hiwiski://wiki_page/$id)'),
        page(id, 'Router'),
      ]);

      expect(index.outgoing('WIKI_PAGE', 'p1').single.itemId, equals(id));
    });

    test(
      'the title is the current one, not the one at the time of writing',
      () {
        // The text still contains the number; the page has since been renamed.
        final index = LinkIndex.from([
          page('p1', 'Internet', text: 'Siehe #WIKI-3.'),
          page('p2', 'Fritzbox', key: 'WIKI-3'),
        ]);

        expect(
          index.outgoing('WIKI_PAGE', 'p1').single.title,
          equals('Fritzbox'),
        );
      },
    );

    test('what is not on this device is not a reference', () {
      // A number that does not exist -- or a page that is not shared with the reader and
      // therefore is not on their device at all. Both are the same case: it drops out
      // entirely instead of showing "access denied".
      final index = LinkIndex.from([
        page('p1', 'Internet', text: 'Siehe #WIKI-99.'),
      ]);

      expect(index.outgoing('WIKI_PAGE', 'p1'), isEmpty);
    });

    test('a reference to itself yields no row', () {
      final index = LinkIndex.from([
        page('p1', 'Internet', key: 'WIKI-1', text: 'Siehe #WIKI-1.'),
      ]);

      expect(index.outgoing('WIKI_PAGE', 'p1'), isEmpty);
      expect(index.incoming('WIKI_PAGE', 'p1'), isEmpty);
    });

    test('the same reference twice is one row', () {
      final index = LinkIndex.from([
        todo('t1', 'Urlaub', text: '#WIKI-3 und noch einmal #WIKI-3'),
        page('p2', 'Router', key: 'WIKI-3'),
      ]);

      expect(index.outgoing('TODO', 't1'), hasLength(1));
    });

    test('across module boundaries', () {
      final index = LinkIndex.from([
        todo('t1', 'Zugang prüfen', text: 'Steht in #WIKI-3.'),
        page('p2', 'Router', key: 'WIKI-3'),
      ]);

      expect(index.incoming('WIKI_PAGE', 'p2').single.itemType, equals('TODO'));
    });

    test('a list is a target by its address', () {
      const id = '01932b3c-4d5e-7f80-8a1b-2c3d4e5f6072';
      final index = LinkIndex.from([
        page('p1', 'Wochenende', text: '[Einkauf](hiwiski://todo_list/$id)'),
        const LinkItem(itemType: 'TODO_LIST', itemId: id, title: 'Einkauf'),
      ]);

      expect(
        index.outgoing('WIKI_PAGE', 'p1').single.itemType,
        equals('TODO_LIST'),
      );
      expect(index.incoming('TODO_LIST', id).single.itemId, equals('p1'));
    });

    test("a comment's links count as the item's it is on", () {
      final index = LinkIndex.from(
        [
          page('p1', 'Internet', text: 'Siehe #WIKI-3.'),
          page('p2', 'Router', key: 'WIKI-3'),
          todo('t1', 'Zugang prüfen', key: 'TD-1'),
        ],
        attached: const [
          AttachedText(itemType: 'WIKI_PAGE', itemId: 'p1', text: '#TD-1?'),
          // Already in the text: still one row.
          AttachedText(itemType: 'WIKI_PAGE', itemId: 'p1', text: '#WIKI-3'),
          // On something not here: nowhere to show.
          AttachedText(itemType: 'CALENDAR', itemId: 'c1', text: '#TD-1'),
        ],
      );

      expect(
        index.outgoing('WIKI_PAGE', 'p1').map((item) => item.itemId),
        equals(['p2', 't1']),
      );
      expect(index.incoming('TODO', 't1').single.itemId, equals('p1'));
    });
  });

  group('the info bar', () {
    Future<void> pumpBar(
      WidgetTester tester,
      double width,
      LinkIndex index,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const bar = InfoBar(
        sections: [ReferencesSections(item: ItemRef.wikiPage('p1'))],
      );
      final wide = width >= HiwiskiMetrics.breakpointWide;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [linkIndexProvider.overrideWithValue(index)],
          child: MaterialApp(
            theme: HiwiskiTheme.light(),
            locale: const Locale('de'),
            localizationsDelegates: const [
              L.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: L.supportedLocales,
            home: Scaffold(
              // This is how the screens use it: on desktop as a column next to the
              // content, otherwise as a section in the content flow.
              body: wide
                  ? const Row(children: [Spacer(), bar])
                  : ListView(children: [bar]),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('on desktop a column of 260', (tester) async {
      await pumpBar(tester, 1200, LinkIndex.from(const []));

      // 260 wide with a line on the left.
      expect(
        tester.getSize(find.byType(InfoBar)).width,
        equals(HiwiskiMetrics.infoRailWidth),
      );
    });

    testWidgets('an empty section says "Keine" (none)', (tester) async {
      await pumpBar(tester, 1200, LinkIndex.from(const []));

      // Twice: once per direction. A section that disappears could not be told apart
      // from "still loading".
      expect(find.text('Keine'), findsNWidgets(2));
    });

    testWidgets('both directions are shown with title and number', (
      tester,
    ) async {
      final index = LinkIndex.from([
        page('p1', 'Internet', text: 'Siehe #WIKI-3.'),
        page('p2', 'Router', key: 'WIKI-3'),
      ]);
      await pumpBar(tester, 1200, index);

      expect(find.text('Router'), findsOneWidget);
      expect(find.text('WIKI-3'), findsOneWidget);
      expect(find.text('Keine'), findsOneWidget);
    });

    testWidgets('more than three fold into a sheet with all of them', (
      tester,
    ) async {
      final index = LinkIndex.from([
        page('p1', 'Internet', text: '#WIKI-1 #WIKI-2 #WIKI-3 #WIKI-4'),
        for (var i = 1; i <= 4; i++) page('t$i', 'Target $i', key: 'WIKI-$i'),
      ]);
      await pumpBar(tester, 1200, index);

      expect(find.text('Target 3'), findsOneWidget);
      expect(find.text('Target 4'), findsNothing);
      expect(find.text('Alle 4 anzeigen'), findsOneWidget);

      await tester.tap(find.byKey(CoreKeys.linkShowAll));
      await tester.pumpAndSettle();
      // The sheet lists all four; the bar behind it still its three.
      expect(find.text('Target 4'), findsOneWidget);
      expect(find.text('Target 1'), findsNWidgets(2));
    });

    testWidgets('on a phone a section below the content', (tester) async {
      await pumpBar(tester, 400, LinkIndex.from(const []));

      // No fixed width, but that of the content -- and a line above it that separates
      // it from the content.
      expect(tester.getSize(find.byType(InfoBar)).width, equals(400));
      expect(
        find.descendant(
          of: find.byType(InfoBar),
          matching: find.byType(Divider),
        ),
        findsOneWidget,
      );
    });
  });

  group('drawing', () {
    Future<void> pump(WidgetTester tester, LinkIndex index, String text) =>
        tester.pumpWidget(
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
              home: Scaffold(body: LinkedProse(text: text)),
            ),
          ),
        );

    testWidgets('a reference becomes a chip with the current title', (
      tester,
    ) async {
      final index = LinkIndex.from([page('p2', 'Fritzbox', key: 'WIKI-3')]);
      await pump(tester, index, 'Zugangsdaten stehen in #WIKI-3.');

      expect(find.byType(LinkChip), findsOneWidget);
      expect(find.text('Fritzbox'), findsOneWidget);
    });

    testWidgets('the brackets of the address form do not remain', (
      tester,
    ) async {
      const id = '01932b3c-4d5e-7f80-8a1b-2c3d4e5f6071';
      final index = LinkIndex.from([page(id, 'Router')]);
      await pump(
        tester,
        index,
        'Siehe [Router](hiwiski://wiki_page/$id) — fertig.',
      );

      expect(find.byType(LinkChip), findsOneWidget);
      expect(find.textContaining('hiwiski://'), findsNothing);
      expect(find.textContaining(']('), findsNothing);
    });

    Future<void> pumpMarkdown(
      WidgetTester tester,
      LinkIndex index,
      String data,
    ) => tester.pumpWidget(
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
          home: Scaffold(body: LinkedMarkdown(data: data)),
        ),
      ),
    );

    testWidgets('in Markdown the number becomes a chip', (tester) async {
      final index = LinkIndex.from([page('p2', 'Fritzbox', key: 'WIKI-3')]);
      await pumpMarkdown(tester, index, 'Zugangsdaten stehen in #WIKI-3.');

      expect(find.byType(LinkChip), findsOneWidget);
      expect(find.text('Fritzbox'), findsOneWidget);
    });

    testWidgets('in Markdown the address does not become an ordinary link', (
      tester,
    ) async {
      const id = '01932b3c-4d5e-7f80-8a1b-2c3d4e5f6071';
      final index = LinkIndex.from([page(id, 'Router')]);
      // Our own inline rule runs **before** Markdown's link rule. Without this order
      // there would be a link here that points nowhere.
      await pumpMarkdown(
        tester,
        index,
        'Siehe [Router](hiwiski://wiki_page/$id).',
      );

      expect(find.byType(LinkChip), findsOneWidget);
      expect(find.textContaining('hiwiski://'), findsNothing);
    });

    testWidgets('in Markdown a reference resolves once the index arrives', (
      tester,
    ) async {
      // A reload in the browser: the page is drawn before the local database has
      // answered, so the first pass sees an empty index.
      final index = StateProvider<LinkIndex>((ref) => LinkIndex.from(const []));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkIndexProvider.overrideWith((ref) => ref.watch(index)),
          ],
          child: MaterialApp(
            theme: HiwiskiTheme.light(),
            localizationsDelegates: const [
              L.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: L.supportedLocales,
            home: const Scaffold(
              body: LinkedMarkdown(data: 'Zugangsdaten stehen in #WIKI-3.'),
            ),
          ),
        ),
      );
      expect(find.byType(LinkChip), findsNothing);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(LinkedMarkdown)),
      );
      container.read(index.notifier).state = LinkIndex.from([
        page('p2', 'Fritzbox', key: 'WIKI-3'),
      ]);
      await tester.pump();

      expect(find.byType(LinkChip), findsOneWidget);
      expect(find.textContaining('#WIKI-3'), findsNothing);
    });

    testWidgets('a heading stays a heading', (tester) async {
      await pumpMarkdown(tester, LinkIndex.from(const []), '# Einkauf');

      expect(find.byType(LinkChip), findsNothing);
      expect(find.text('Einkauf'), findsOneWidget);
    });

    testWidgets('a reference to nowhere stays plain text', (tester) async {
      await pump(tester, LinkIndex.from(const []), 'Siehe #TD-99.');

      // No "access denied" and no chip: existence is a piece of information too.
      expect(find.byType(LinkChip), findsNothing);
      expect(find.textContaining('#TD-99'), findsOneWidget);
    });

    testWidgets('an address to nowhere keeps its title', (tester) async {
      const id = '01932b3c-4d5e-7f80-8a1b-2c3d4e5f6071';
      await pump(
        tester,
        LinkIndex.from(const []),
        'Siehe [Router](hiwiski://wiki_page/$id) — fertig.',
      );

      // The writer's words remain. Swallowing them entirely would be worse than a
      // reference without a target.
      expect(find.byType(LinkChip), findsNothing);
      expect(find.textContaining('Siehe Router — fertig.'), findsOneWidget);
    });

    // A title with brackets ended the label at its own "]": the link fell apart into
    // "[Packing [summer]](" and ")" around a dead address.
    testWidgets('a title with brackets stays one link', (tester) async {
      const id = '01932b3c-4d5e-7f80-8a1b-2c3d4e5f6071';
      final text =
          'See ${UriReference.markdown('WIKI_PAGE', id, 'Packing [summer]')} now.';
      expect(text, contains(r'[Packing \[summer\]]'));
      expect(
        parseReferences(text),
        equals([const UriReference('WIKI_PAGE', id)]),
      );

      await pump(tester, LinkIndex.from(const []), text);

      expect(find.textContaining('See Packing [summer] now.'), findsOneWidget);
    });
  });
}
