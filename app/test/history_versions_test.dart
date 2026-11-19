import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/components/history/history_view_model.dart';
import 'package:hiwiski/components/history/view/history_keys.dart';
import 'package:hiwiski/components/history/view/history_section.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/common/history_rows.dart';
import 'package:hiwiski/domain/common/item_ref.dart';

/// **A page's changes and versions are one list**: a change that
/// left a version opens it, and versions without a change keep a row of their own.
/// Two lists side by side showed the same saves twice — one knowing what changed,
/// the other what the text was.
void main() {
  final created = DateTime(2026, 10, 1, 8);
  final edited = DateTime(2026, 10, 24, 9, 30);
  final tagged = DateTime(2026, 10, 25, 18);

  HistoryEntry entry(int seq, DateTime at, List<String> fields) =>
      .new(seq: seq, at: at, op: .upsert, fields: fields);
  Revision revision(
    String id,
    DateTime at, {
    int? changeSeq,
    RevisionKind kind = .save,
  }) => .new(
    id: id,
    seq: 1,
    title: 'Router',
    createdAt: at,
    kind: kind,
    changeSeq: changeSeq,
  );

  group('historyRows', () {
    test('a change that left a version is one row that opens it', () {
      final rows = historyRows(
        [
          entry(3, tagged, ['tags']),
          entry(2, edited, ['content']),
        ],
        [revision('r2', edited.add(const Duration(seconds: 1)), changeSeq: 2)],
      );

      expect(rows.map((row) => row.entry?.seq), equals([3, 2]));
      expect(rows.map((row) => row.revision?.id), equals([null, 'r2']));
    });

    test('versions without their change keep a row of their own', () {
      final rows = historyRows(
        [
          entry(2, edited, ['content']),
        ],
        [
          // Older than the log reaches back.
          revision('r1', created, changeSeq: 1),
          // The losing side of a conflict: never written.
          revision('c1', tagged, kind: .conflict),
        ],
      );

      expect(
        rows.map((row) => (row.entry?.seq, row.revision?.id)),
        equals([(null, 'c1'), (2, null), (null, 'r1')]),
      );
    });
  });

  Future<void> pumpHistory(
    WidgetTester tester,
    Widget Function(String id) versionView,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyViewModelProvider.overrideWith2(
            (_) => _FixedHistory([
              HistoryRow.change(entry(3, tagged, ['tags'])),
              HistoryRow.change(
                entry(2, edited, ['content']),
                revision: revision('r2', edited, changeSeq: 2),
              ),
              HistoryRow.version(revision('c1', created, kind: .conflict)),
            ]),
          ),
        ],
        child: MaterialApp(
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
            body: HistorySection(
              // Created 2026-01-01 — before the history reaches back, so no row
              // is its creation.
              item: const ItemRef.wikiPage(
                '019b76da-a800-7000-8000-000000000000',
              ),
              versionView: versionView,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final sheet = find.byWidgetPredicate(
    (widget) => widget is Dialog || widget is BottomSheet,
  );

  testWidgets('a version opens inside the history sheet, and back turns back', (
    tester,
  ) async {
    await pumpHistory(tester, (id) => Text('Version $id'));
    expect(find.textContaining('kept a conflicting version'), findsOneWidget);

    // A row of the info bar opens the sheet at its version.
    await tester.tap(find.textContaining('changed: Text'));
    await tester.pumpAndSettle();
    expect(find.text('Version r2'), findsOneWidget);

    // Back turns to the list — in the same sheet, not a second one.
    await tester.tap(find.byKey(HistoryKeys.versionBack));
    await tester.pumpAndSettle();
    expect(find.text('Version r2'), findsNothing);
    expect(sheet, findsOneWidget);
    final conflict = find.descendant(
      of: sheet,
      matching: find.byKey(HistoryKeys.version('c1')),
    );
    expect(conflict, findsOneWidget);

    await tester.tap(conflict);
    await tester.pumpAndSettle();
    expect(find.text('Version c1'), findsOneWidget);
    expect(sheet, findsOneWidget);

    // A swipe turns back as well, like a page.
    await tester.fling(find.text('Version c1'), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Version c1'), findsNothing);
    expect(conflict, findsOneWidget);
  });

  testWidgets(
    'a swipe back stops at the list',
    (tester) async {
      await pumpHistory(tester, (id) => Text('Version $id'));
      await tester.tap(find.textContaining('changed: Text'));
      await tester.pumpAndSettle();
      final page = tester.getTopLeft(find.text('Version r2')).dx;

      // Far past the list, the finger still down.
      final swipe = await tester.startGesture(
        tester.getCenter(find.text('Version r2')),
      );
      for (int step = 0; step < 12; step++) {
        await swipe.moveBy(const Offset(60, 0));
        await tester.pump();
      }
      final row = find.descendant(
        of: sheet,
        matching: find.byKey(HistoryKeys.version('c1')),
      );
      expect(
        tester.getTopLeft(row).dx,
        lessThanOrEqualTo(page),
        reason: 'the list does not follow the finger past its place',
      );

      await swipe.up();
      await tester.pumpAndSettle();
      expect(find.text('Version r2'), findsNothing);
      expect(row, findsOneWidget);
    },
    // Where scrolling bounces by default.
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'the sheet is as high as its pages need, and never shrinks back',
    (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // r2 is short, the conflict version c1 long.
      await pumpHistory(
        tester,
        (id) => SizedBox(height: id == 'c1' ? 300 : 20, child: Text(id)),
      );

      await tester.tap(find.textContaining('changed: Text'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(HistoryKeys.versionBack));
      await tester.pumpAndSettle();
      final withList = tester.getSize(sheet).height;
      expect(withList, lessThan(844 / 2), reason: 'three rows, not the screen');

      await tester.tap(
        find.descendant(
          of: sheet,
          matching: find.byKey(HistoryKeys.version('c1')),
        ),
      );
      await tester.pumpAndSettle();
      final withVersion = tester.getSize(sheet).height;
      expect(
        withVersion,
        greaterThan(withList),
        reason: 'the version needs more',
      );

      await tester.tap(find.byKey(HistoryKeys.versionBack));
      await tester.pumpAndSettle();
      expect(tester.getSize(sheet).height, equals(withVersion));
    },
  );
}

class _FixedHistory extends HistoryViewModel {
  _FixedHistory(this._rows);

  final List<HistoryRow> _rows;

  @override
  Future<HistoryState> build(ItemRef item) async => HistoryState(
    history: History(
      reachesBack: DateTime(2026, 7, 25),
      entries: [for (final row in _rows) ?row.entry],
    ),
    members: const [],
    rows: _rows,
  );
}
