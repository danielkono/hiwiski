import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/core/api/generated/export.dart' hide Mutation;
import 'package:hiwiski/components/member_avatar/view/member_avatar.dart';
import 'package:hiwiski/data/family/family_repository.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/theme/hiwiski_metrics.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/sync/local_writes.dart';
import 'package:hiwiski/core/sync/outbox.dart';
import 'package:hiwiski/core/sync/sync_engine.dart';
import 'package:hiwiski/core/sync/sync_status.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/core/ui/ui_keys.dart';
import 'package:hiwiski/domain/wiki/mindmap.dart';
import 'package:hiwiski/features/wiki/mindmap/view/mindmap_conflict_bar.dart';
import 'package:hiwiski/features/wiki/mindmap/view/mindmap_corner.dart';
import 'package:hiwiski/features/wiki/mindmap/view/mindmap_keys.dart';
import 'package:hiwiski/features/wiki/mindmap/view/mindmap_results.dart';
import 'package:hiwiski/features/wiki/mindmap/view/mindmap_screen.dart';
import 'package:hiwiski/features/wiki/page/view/mindmap/mindmap_preview_card.dart';
import 'package:hiwiski/features/wiki/view/mindmap/mindmap_link.dart';
import 'package:hiwiski/features/wiki/view/mindmap/mindmap_picture.dart';
import 'package:hiwiski/features/wiki/view/mindmap/mindmap_scene.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// The mind map full screen: read and searched by everyone who sees the page,
/// edited with "Edit" — each change written at once — and a conflict decided for the
/// one element it is about.
void main() {
  late HiwiskiDatabase db;
  late ProviderContainer container;
  late String pageId;
  late String meer;
  late String berge;

  /// Whether a drag under way is expected to show guides.
  bool snapping = true;

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1000, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
          home: MindmapScreen(pageId: pageId),
        ),
      ),
    );
    await settle(tester);
  }

  /// [banner]: the sync banner as it is, reading the conflicts — otherwise quiet.
  Future<ProviderContainer> containerFor({
    bool banner = false,
    FamilyRepository? family,
  }) async => ProviderContainer(
    retry: noRetry,
    overrides: [
      databaseProvider.overrideWithValue(db),
      localSettingsProvider.overrideWithValue(await LocalSettings.open()),
      deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
      sessionAt(signedInAnna),
      familyRepositoryProvider.overrideWithValue(family ?? NoFamily()),
      if (banner) ...[
        syncStatusProvider.overrideWithValue(const SyncStatus()),
        servedWebAppProvider.overrideWithValue(false),
      ] else
        ...quietSync,
      // Nothing to sync with: a run would only wait to try again.
      localWritesProvider.overrideWith(
        (ref) => LocalWrites(db: db, outbox: Outbox(db), sync: _NoSync()),
      ),
    ],
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = HiwiskiDatabase(NativeDatabase.memory());
    container = await containerFor();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> seed(WidgetTester tester) => tester.runAsync(() async {
    pageId = await container
        .read(wikiRepositoryProvider)
        .createPage(title: 'Urlaub', kind: PageKinds.mindmap);
    final maps = container.read(mindmapRepositoryProvider);
    meer = await maps.addNode(
      pageId: pageId,
      kind: MindmapKinds.plain,
      x: 0,
      y: 0,
      width: 160,
      height: 40,
      text: 'Meer',
    );
    berge = await maps.addNode(
      pageId: pageId,
      kind: MindmapKinds.plain,
      x: 300,
      y: 0,
      width: 160,
      height: 40,
      text: 'Berge',
    );
  });

  testWidgets('the map shows its elements and is edited with Edit', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);

    expect(find.text('Meer'), findsOneWidget);
    expect(find.text('Berge'), findsOneWidget);
    expect(find.byKey(MindmapKeys.tool(MindmapKinds.plain)), findsNothing);

    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    // Written where it lands, no sheet over the map; kept once it is left.
    await pick(
      tester,
      MindmapKeys.addMenu,
      MindmapKeys.tool(MindmapKinds.plain),
    );
    await settle(tester);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.enterText(find.byKey(MindmapKeys.textField), 'Wüste');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    final rows = await tester.runAsync(() => db.select(db.mindmapNodes).get());
    expect(
      rows!.map((row) => row.body),
      containsAll(['Meer', 'Berge', 'Wüste']),
    );
    expect(find.text('Wüste'), findsOneWidget);
    // Just as large as its one word.
    final placed = rows.firstWhere((row) => row.body == 'Wüste');
    expect(placed.width, lessThan(HiwiskiMetrics.mindmapPlainWrap / 2));
    // Placed and selected: what can be done with it shows.
    expect(find.byKey(MindmapKeys.delete), findsOneWidget);
  });

  testWidgets('what is typed stays in view, word for word', (tester) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    await pick(
      tester,
      MindmapKeys.addMenu,
      MindmapKeys.tool(MindmapKinds.plain),
    );
    await settle(tester);

    for (final text in ['Hallo', 'Hallo Welt', 'Hallo Welt und Meer']) {
      await tester.enterText(find.byKey(MindmapKeys.textField), text);
      await tester.pump();
      final field = (tester.state(
        find.byType(EditableText),
      ) as EditableTextState).renderEditable;
      final last = field
          .getBoxesForSelection(
            TextSelection(
              baseOffset: text.length - 1,
              extentOffset: text.length,
            ),
          )
          .last;
      final element = tester.getSize(
        find
            .ancestor(
              of: find.byType(EditableText),
              matching: find.byType(MindmapElementView),
            )
            .first,
      );
      // On the line it was typed on, inside the snippet — not broken onto a line
      // the snippet cuts off.
      expect(last.bottom, lessThanOrEqualTo(element.height), reason: text);
      expect(field.size.width, equals(element.width), reason: text);
    }
  });

  testWidgets('a snippet is rewritten in place, and emptied it goes', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    // Selected with a tap, written with the next.
    await tester.tap(find.text('Meer'));
    await settle(tester);
    await tester.tap(find.text('Meer'));
    await settle(tester);

    await tester.enterText(
      find.byKey(MindmapKeys.textField),
      'Meer und Strand',
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    Future<String?> textOf(String id) async => (await tester.runAsync(
      () => (db.select(
        db.mindmapNodes,
      )..where((row) => row.id.equals(id))).getSingle(),
    ))?.body;
    expect(await textOf(meer), equals('Meer und Strand'));
    expect(find.text('Meer und Strand'), findsOneWidget);

    await tester.tap(find.text('Meer und Strand'));
    await settle(tester);
    await tester.enterText(find.byKey(MindmapKeys.textField), '');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    final left = await tester.runAsync(
      () => (db.select(
        db.mindmapNodes,
      )..where((row) => row.id.equals(meer))).getSingle(),
    );
    expect(left?.deletedAt, isNotNull);
  });

  testWidgets('on a phone, what is typed is kept when another snippet starts', (
    tester,
  ) async {
    await seed(tester);
    await open(tester, size: const Size(390, 844));
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    Future<List<String>> texts() async => [
      for (final row in (await tester.runAsync(
        () => db.select(db.mindmapNodes).get(),
      ))!)
        if (row.deletedAt == null) row.body,
    ];

    // One there rewritten, and — the field still in hand, as on a phone, where a
    // tap in the corner leaves the keyboard up — "Edit content" tapped for it: what
    // is typed stays in the field.
    await tester.tap(find.text('Meer'));
    await settle(tester);
    await tester.tap(find.text('Meer'));
    await settle(tester);
    await tester.enterText(
      find.byKey(MindmapKeys.textField),
      'Meer und Strand',
    );
    await tester.pump();
    await tester.tap(find.byKey(MindmapKeys.editContent));
    await settle(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(MindmapKeys.textField))
          .controller
          ?.text,
      equals('Meer und Strand'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(await texts(), contains('Meer und Strand'));

    // A new snippet written, and another one begun, the field still in hand.
    await pick(
      tester,
      MindmapKeys.addMenu,
      MindmapKeys.tool(MindmapKinds.plain),
    );
    await settle(tester);
    await tester.enterText(find.byKey(MindmapKeys.textField), 'Hallo');
    await tester.pump();
    await pick(
      tester,
      MindmapKeys.addMenu,
      MindmapKeys.tool(MindmapKinds.plain),
    );
    await settle(tester);
    await tester.enterText(find.byKey(MindmapKeys.textField), 'Welt');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(await texts(), containsAll(['Hallo', 'Welt']));
  });

  testWidgets('a member of the family is placed by their picture', (
    tester,
  ) async {
    await seed(tester);
    container.dispose();
    container = await containerFor(family: _Family());
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);

    await pick(
      tester,
      MindmapKeys.addMenu,
      MindmapKeys.tool(MindmapKinds.member),
    );
    await settle(tester);
    await tester.tap(find.byKey(MindmapKeys.member('ben')));
    await settle(tester);

    final rows = await tester.runAsync(() => db.select(db.mindmapNodes).get());
    final placed = rows!.firstWhere((row) => row.kind == MindmapKinds.member);
    expect(placed.target, equals('hiwiski://member/ben'));
    expect(placed.width, equals(placed.height));
    expect(
      tester
          .widgetList<MemberAvatar>(find.byType(MemberAvatar))
          .map((avatar) => avatar.displayName),
      equals(['Ben']),
    );

    // Resized, the next one placed is as large.
    final zoom = tester.widget<MindmapScene>(find.byType(MindmapScene)).zoom;
    await tester.drag(
      find.byKey(ValueKey('${placed.id}-resize')),
      Offset(60 * zoom, 60 * zoom),
    );
    await settle(tester);
    final resized = (await tester.runAsync(
      () => (db.select(
        db.mindmapNodes,
      )..where((row) => row.id.equals(placed.id))).getSingle(),
    ))!;
    expect(resized.width, greaterThan(placed.width));
    await pick(
      tester,
      MindmapKeys.addMenu,
      MindmapKeys.tool(MindmapKinds.member),
    );
    await settle(tester);
    await tester.tap(find.byKey(MindmapKeys.member('ben')));
    await settle(tester);
    final again =
        (await tester.runAsync(() => db.select(db.mindmapNodes).get()))!
            .where(
              (row) => row.kind == MindmapKinds.member && row.id != placed.id,
            )
            .single;
    expect((
      again.width,
      again.height,
    ), equals((resized.width, resized.height)));
  });

  testWidgets('a moved element snaps to another\'s top, a guide shows where', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    final guides = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          '${widget.painter.runtimeType}' == '_GuidesPainter',
    );
    Future<int> bergeTop() async => (await tester.runAsync(
      () => (db.select(
        db.mindmapNodes,
      )..where((row) => row.id.equals(berge))).getSingle(),
    ))!.y;

    // Down past the finger's slop and back up to 4 below Meer's top.
    Future<void> nudge() async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Berge')),
      );
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -26));
      await tester.pump();
      expect(guides, snapping ? findsOneWidget : findsNothing);
      await gesture.up();
      await settle(tester);
    }

    snapping = true;
    await nudge();
    expect(await bergeTop(), equals(0));
    expect(guides, findsNothing);

    // Switched off, it stays where it was let go.
    await pick(tester, MindmapKeys.toolsMenu, MindmapKeys.snap);
    await settle(tester);
    snapping = false;
    await nudge();
    final zoom = tester.widget<MindmapScene>(find.byType(MindmapScene)).zoom;
    expect(await bergeTop(), equals((4 / zoom).round()));
  });

  testWidgets('a resized element takes another\'s height', (tester) async {
    await seed(tester);
    // Notes: a snippet's height is its text's.
    final small = await tester.runAsync(() async {
      final maps = container.read(mindmapRepositoryProvider);
      await maps.addNode(
        pageId: pageId,
        kind: MindmapKinds.note,
        x: 600,
        y: 300,
        width: 160,
        height: 80,
        text: 'Wüste',
      );
      return maps.addNode(
        pageId: pageId,
        kind: MindmapKinds.note,
        x: 0,
        y: 200,
        width: 160,
        height: 40,
        text: 'Steppe',
      );
    });
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    await tester.tap(find.text('Steppe'));
    await settle(tester);
    final zoom = tester.widget<MindmapScene>(find.byType(MindmapScene)).zoom;

    // To 3 short of the other note's height: it takes it.
    await tester.drag(
      find.byKey(ValueKey('$small-resize')),
      Offset(0, 37 * zoom),
    );
    await settle(tester);

    final row = await tester.runAsync(
      () => (db.select(
        db.mindmapNodes,
      )..where((row) => row.id.equals(small!))).getSingle(),
    );
    expect(row!.height, equals(80));
  });

  testWidgets('a group is aligned and made one height, each one step', (
    tester,
  ) async {
    await seed(tester);
    final notes = await tester.runAsync(() async {
      final maps = container.read(mindmapRepositoryProvider);
      return [
        await maps.addNode(
          pageId: pageId,
          kind: MindmapKinds.note,
          x: 0,
          y: 200,
          width: 200,
          height: 100,
          text: 'Erste',
        ),
        await maps.addNode(
          pageId: pageId,
          kind: MindmapKinds.note,
          x: 300,
          y: 250,
          width: 120,
          height: 60,
          text: 'Zweite',
        ),
      ];
    });
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    Future<List<Rect>> boxes() async => [
      for (final id in notes!)
        switch (await tester.runAsync(
          () => (db.select(
            db.mindmapNodes,
          )..where((row) => row.id.equals(id))).getSingle(),
        )) {
          final row? => Rect.fromLTWH(
            row.x.toDouble(),
            row.y.toDouble(),
            row.width.toDouble(),
            row.height.toDouble(),
          ),
          null => Rect.zero,
        },
    ];
    // A rectangle round the two notes.
    Rect around(String text) => tester.getRect(
      find
          .ancestor(
            of: find.text(text),
            matching: find.byType(MindmapElementView),
          )
          .first,
    );
    final area = around('Erste').expandToInclude(around('Zweite')).inflate(16);
    await pick(tester, MindmapKeys.toolsMenu, MindmapKeys.rectangle);
    await settle(tester);
    await tester.dragFrom(area.topLeft, area.bottomRight - area.topLeft);
    await settle(tester);

    Future<void> command(String name) async {
      if (find.byKey(MindmapKeys.align).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(MindmapKeys.align));
        await settle(tester);
      }
      for (
        int turn = 0;
        find.byKey(MindmapKeys.arrange(name)).hitTestable().evaluate().isEmpty;
        turn++
      ) {
        if (turn > 5) fail('$name is not on the ring');
        await turnCorner(tester);
      }
      await tester.tap(find.byKey(MindmapKeys.arrange(name)));
      await settle(tester);
    }

    final before = await boxes();
    await command('left');
    expect((await boxes()).map((box) => box.left), everyElement(0));
    await tester.tap(find.byKey(MindmapKeys.undo));
    await settle(tester);
    expect(await boxes(), equals(before));

    await command('sameHeight');
    final sized = await boxes();
    expect(sized.map((box) => box.height), everyElement(100));
    // The height alone: the second keeps its width.
    expect(sized[1].width, equals(120));
    await tester.tap(find.byKey(MindmapKeys.undo));
    await settle(tester);
    expect(await boxes(), equals(before));
  });

  testWidgets('with the grid on, a moved element lands on it', (tester) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    await pick(tester, MindmapKeys.toolsMenu, MindmapKeys.grid);
    await settle(tester);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            '${widget.painter.runtimeType}' == '_GridPainter',
      ),
      findsOneWidget,
    );

    await tester.drag(find.text('Berge'), const Offset(37, 133));
    await settle(tester);
    final row = await tester.runAsync(
      () => (db.select(
        db.mindmapNodes,
      )..where((row) => row.id.equals(berge))).getSingle(),
    );
    const grid = HiwiskiMetrics.mindmapGrid;
    expect(row!.x % grid, equals(0));
    expect(row.y % grid, equals(0));

    // Snapping off is off for the grid too: it stays, only to be seen.
    await pick(tester, MindmapKeys.toolsMenu, MindmapKeys.snap);
    await settle(tester);
    final zoom = tester.widget<MindmapScene>(find.byType(MindmapScene)).zoom;
    await tester.drag(find.text('Berge'), const Offset(37, 53));
    await settle(tester);
    final moved = await tester.runAsync(
      () => (db.select(
        db.mindmapNodes,
      )..where((row) => row.id.equals(berge))).getSingle(),
    );
    expect(moved!.x, closeTo(row.x + 37 / zoom, 1));
    expect(moved.y, closeTo(row.y + 53 / zoom, 1));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            '${widget.painter.runtimeType}' == '_GridPainter',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the pen draws a stroke, the eraser swipes it away', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    await pick(tester, MindmapKeys.drawMenu, MindmapKeys.pen);
    await settle(tester);

    // A line across empty canvas, from where the finger came down.
    await tester.dragFrom(const Offset(200, 600), const Offset(200, 0));
    // A frame later, before the database has answered: there, not gone for a
    // moment. And once it has: there once, not twice.
    final drawnStrokes = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is StrokePainter,
    );
    await tester.pump();
    expect(drawnStrokes, findsOneWidget);
    await settle(tester);
    expect(drawnStrokes, findsOneWidget);
    Future<List<MindmapNodeRow>> strokes() async => [
      for (final row in (await tester.runAsync(
        () => db.select(db.mindmapNodes).get(),
      ))!)
        if (row.kind == MindmapKinds.drawing) row,
    ];
    final drawn = (await strokes()).single;
    expect(drawn.points, isNotNull);
    expect(drawn.deletedAt, isNull);
    // As wide as the line went, and the pen's width on both sides.
    expect(drawn.width, closeTo(200 + HiwiskiMetrics.mindmapPenWidths[1], 2));

    // Put down, the stroke is selected on its line — with neither a dot to connect
    // it nor a corner to resize it.
    await pick(tester, MindmapKeys.drawMenu, MindmapKeys.pen);
    await settle(tester);
    await pick(tester, MindmapKeys.toolsMenu, MindmapKeys.drawings);
    await settle(tester);
    expect(drawnStrokes, findsNothing);
    await pick(tester, MindmapKeys.toolsMenu, MindmapKeys.drawings);
    await settle(tester);
    expect(drawnStrokes, findsOneWidget);
    await tester.tapAt(const Offset(300, 600));
    await settle(tester);
    expect(find.byKey(MindmapKeys.delete), findsOneWidget);
    expect(find.byKey(ValueKey('${drawn.id}-handle')), findsNothing);
    expect(find.byKey(ValueKey('${drawn.id}-resize')), findsNothing);

    // The eraser across it, top to bottom: gone with the swipe. Let go of the
    // stroke first: while something is selected, the corner holds its choices.
    await tester.tap(find.byKey(MindmapKeys.release));
    await settle(tester);
    await pick(tester, MindmapKeys.drawMenu, MindmapKeys.eraser);
    await settle(tester);
    await tester.dragFrom(const Offset(300, 540), const Offset(0, 120));
    await settle(tester);
    expect((await strokes()).single.deletedAt, isNotNull);

    // And back with "Undo".
    await tester.tap(find.byKey(MindmapKeys.undo));
    await settle(tester);
    expect((await strokes()).single.deletedAt, isNull);
  });

  group('Undo takes back what is seen, not only what is stored', () {
    final strokesSeen = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is StrokePainter,
    );
    Future<List<MindmapNodeRow>> living(WidgetTester tester) async => [
      for (final row in (await tester.runAsync(
        () => db.select(db.mindmapNodes).get(),
      ))!)
        if (row.deletedAt == null) row,
    ];
    Future<void> step(WidgetTester tester, ValueKey<String> key) async {
      await tester.tap(find.byKey(key));
      await settle(tester);
    }

    testWidgets('strokes, one by one, back and forth', (tester) async {
      await seed(tester);
      await open(tester);
      await step(tester, MindmapKeys.edit);
      await pick(tester, MindmapKeys.drawMenu, MindmapKeys.pen);
      await settle(tester);
      await tester.dragFrom(const Offset(200, 500), const Offset(200, 0));
      await settle(tester);
      await tester.dragFrom(const Offset(200, 650), const Offset(200, 0));
      await settle(tester);
      expect(strokesSeen, findsNWidgets(2));

      // The last drawn first — and gone from sight, not only from the map.
      await step(tester, MindmapKeys.undo);
      expect(strokesSeen, findsOneWidget);
      final left = [
        for (final row in await living(tester))
          if (row.kind == MindmapKinds.drawing) row,
      ];
      expect(left.single.y, lessThan(550));
      await step(tester, MindmapKeys.undo);
      expect(strokesSeen, findsNothing);

      await step(tester, MindmapKeys.redo);
      expect(strokesSeen, findsOneWidget);
      await step(tester, MindmapKeys.redo);
      expect(strokesSeen, findsNWidgets(2));
    });

    testWidgets('a snippet written in place, new and rewritten', (
      tester,
    ) async {
      await seed(tester);
      await open(tester);
      await step(tester, MindmapKeys.edit);
      await pick(
        tester,
        MindmapKeys.addMenu,
        MindmapKeys.tool(MindmapKinds.plain),
      );
      await settle(tester);
      await tester.enterText(find.byKey(MindmapKeys.textField), 'Wüste');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.text('Wüste'), findsOneWidget);

      await step(tester, MindmapKeys.undo);
      expect(find.text('Wüste'), findsNothing);
      await step(tester, MindmapKeys.redo);
      expect(find.text('Wüste'), findsOneWidget);

      // Rewritten, and taken back: the old words again.
      await tester.tap(find.text('Meer'));
      await settle(tester);
      await tester.tap(find.text('Meer'));
      await settle(tester);
      await tester.enterText(find.byKey(MindmapKeys.textField), 'Ozean');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.text('Ozean'), findsOneWidget);
      await step(tester, MindmapKeys.undo);
      expect(find.text('Ozean'), findsNothing);
      expect(find.text('Meer'), findsOneWidget);
    });

    testWidgets('a move, taken back at once', (tester) async {
      await seed(tester);
      await open(tester);
      await step(tester, MindmapKeys.edit);
      final element = find
          .ancestor(
            of: find.text('Berge'),
            matching: find.byType(MindmapElementView),
          )
          .first;
      final before = tester.getRect(element);
      await tester.dragFrom(before.center, const Offset(100, 50));
      // Taken back while the moved place is still held.
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      await step(tester, MindmapKeys.undo);
      expect(tester.getRect(element).topLeft, equals(before.topLeft));
    });
  });

  testWidgets('the corner turns to show the choices that do not fit', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    // A stroke, so that the tools hold all they can: six choices.
    await pick(tester, MindmapKeys.drawMenu, MindmapKeys.pen);
    await settle(tester);
    await tester.dragFrom(const Offset(300, 300), const Offset(80, 40));
    await settle(tester);
    await pick(tester, MindmapKeys.drawMenu, MindmapKeys.pen);
    await settle(tester);

    await tester.tap(find.byKey(MindmapKeys.toolsMenu));
    await settle(tester);
    expect(find.byKey(MindmapKeys.select), findsOneWidget);
    expect(find.byKey(MindmapKeys.picture), findsNothing);

    // Past the left edge too: there the angle jumps from -π to π, and the turn
    // must not jump with it.
    await turnCorner(tester);
    expect(find.byKey(MindmapKeys.picture).hitTestable(), findsOneWidget);
    expect(find.byKey(MindmapKeys.select), findsNothing);
  });

  testWidgets('the corner shows the first choices of what is selected next', (
    tester,
  ) async {
    List<MindmapCornerOption> choices(String name, int count) => [
      for (int i = 0; i < count; i++)
        MindmapCornerOption(
          key: ValueKey('$name$i'),
          icon: Icons.edit,
          label: '$name$i',
          onTap: () {},
        ),
    ];
    Future<void> show(List<MindmapCornerOption> selection) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: HiwiskiTheme.light(),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: MindmapCorner(
                    menus: const [],
                    open: null,
                    onOpen: (_) {},
                    compact: false,
                    backKey: MindmapKeys.closeMenu,
                    backLabel: 'Back',
                    onBack: () {},
                    selection: selection,
                    onRelease: () {},
                    releaseKey: MindmapKeys.release,
                    releaseLabel: 'Release',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await settle(tester);
    }

    // One with many choices, turned on to its last …
    await show(choices('note', 12));
    for (
      int turn = 0;
      find.byKey(const ValueKey('note11')).hitTestable().evaluate().isEmpty;
      turn++
    ) {
      if (turn > _turnsAtMost) fail('the last choice is not on the ring');
      await turnCorner(tester);
    }
    // … then one with fewer, of another kind: its first choice is there.
    await show(choices('stroke', 8));
    expect(find.byKey(const ValueKey('stroke0')).hitTestable(), findsOneWidget);
  });

  testWidgets('a group is selected with a rectangle and moved as one', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    MindmapElementView viewOf(String text) => tester.widget(
      find
          .ancestor(
            of: find.text(text),
            matching: find.byType(MindmapElementView),
          )
          .first,
    );
    Rect rectOf(String text) => tester.getRect(
      find
          .ancestor(
            of: find.text(text),
            matching: find.byType(MindmapElementView),
          )
          .first,
    );
    final meerBefore = rectOf('Meer');
    final bergeBefore = rectOf('Berge');

    // A rectangle round both.
    await pick(tester, MindmapKeys.toolsMenu, MindmapKeys.rectangle);
    await settle(tester);
    final around = meerBefore.expandToInclude(bergeBefore).inflate(20);
    await tester.dragFrom(around.topLeft, around.bottomRight - around.topLeft);
    await settle(tester);
    expect(viewOf('Meer').selected, isTrue);
    expect(viewOf('Berge').selected, isTrue);

    // One dragged, both go.
    await tester.dragFrom(meerBefore.center, const Offset(40, 60));
    await settle(tester);
    expect(
      rectOf('Meer').topLeft,
      equals(meerBefore.topLeft + const Offset(40, 60)),
    );
    expect(
      rectOf('Berge').topLeft,
      equals(bergeBefore.topLeft + const Offset(40, 60)),
    );

    // Taken away together — and back with one "Undo".
    await tester.tap(find.byKey(MindmapKeys.delete));
    await settle(tester);
    expect(find.text('Meer'), findsNothing);
    expect(find.text('Berge'), findsNothing);
    await tester.tap(find.byKey(MindmapKeys.undo));
    await settle(tester);
    expect(find.text('Meer'), findsOneWidget);
    expect(find.text('Berge'), findsOneWidget);
  });

  testWidgets('strokes out of sight are not taken into a group', (
    tester,
  ) async {
    await seed(tester);
    final stroke = (await tester.runAsync(
      () => container
          .read(mindmapRepositoryProvider)
          .addNode(
            pageId: pageId,
            kind: MindmapKinds.drawing,
            x: 180,
            y: 0,
            width: 100,
            height: 40,
            points: '0,5000 10000,5000',
            strokeWidth: 4,
          ),
    ))!;
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    final meerAt = tester.getRect(find.text('Meer'));
    final bergeAt = tester.getRect(find.text('Berge'));

    // The strokes hidden, a rectangle round everything — and what it took deleted.
    await pick(tester, MindmapKeys.toolsMenu, MindmapKeys.drawings);
    await settle(tester);
    // Closed and opened again: the ring turned to the switch starts at its first
    // choice once more.
    await tester.tap(find.byKey(MindmapKeys.toolsMenu));
    await settle(tester);
    await pick(tester, MindmapKeys.toolsMenu, MindmapKeys.rectangle);
    await settle(tester);
    final around = meerAt.expandToInclude(bergeAt).inflate(40);
    await tester.dragFrom(around.topLeft, around.bottomRight - around.topLeft);
    await settle(tester);
    await tester.tap(find.byKey(MindmapKeys.delete));
    await settle(tester);

    Future<MindmapNodeRow> row(String id) async => (await tester.runAsync(
      () => (db.select(
        db.mindmapNodes,
      )..where((row) => row.id.equals(id))).getSingle(),
    ))!;
    expect((await row(meer)).deletedAt, isNotNull);
    expect((await row(stroke)).deletedAt, isNull);
  });

  testWidgets('a text size of its own, as a number', (tester) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    await tester.tap(find.text('Meer'));
    await settle(tester);

    await tester.tap(find.byKey(MindmapKeys.textSize));
    await settle(tester);
    await tester.enterText(find.byKey(MindmapKeys.ownNumber), '30');
    await tester.pump();
    await tester.tap(find.byKey(MindmapKeys.ownApply));
    await settle(tester);

    final row = await tester.runAsync(
      () => (db.select(
        db.mindmapNodes,
      )..where((row) => row.id.equals(meer))).getSingle(),
    );
    expect(row!.textSize, equals('30'));
    expect(
      tester.widget<Text>(find.text('Meer')).style?.fontSize ??
          DefaultTextStyle.of(tester.element(find.text('Meer'))).style.fontSize,
      equals(30),
    );
  });

  testWidgets('a text size chosen while rewriting sizes for the new text', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    await tester.tap(find.text('Meer'));
    await settle(tester);
    await tester.tap(find.text('Meer'));
    await settle(tester);
    const text = 'Meer und Strand und Dünen am Abend';
    await tester.enterText(find.byKey(MindmapKeys.textField), text);
    await tester.pump();
    Future<MindmapNodeRow> row() async => (await tester.runAsync(
      () => (db.select(
        db.mindmapNodes,
      )..where((row) => row.id.equals(meer))).getSingle(),
    ))!;

    // The sheet takes the field's focus: what is typed is written first.
    await tester.tap(find.byKey(MindmapKeys.textSize));
    await settle(tester);
    final written = await row();
    expect(written.body, equals(text));
    await tester.enterText(find.byKey(MindmapKeys.ownNumber), '30');
    await tester.pump();
    await tester.tap(find.byKey(MindmapKeys.ownApply));
    await settle(tester);

    final box = MindmapElementView.plainBoxOf(
      tester.element(find.byType(MindmapScreen)),
      text,
      '30',
      maxWidth: math.max(
        written.width.toDouble(),
        HiwiskiMetrics.mindmapPlainWrap,
      ),
    );
    final sized = await row();
    expect(sized.body, equals(text));
    expect((
      sized.width,
      sized.height,
    ), equals((box.width.round(), box.height.round())));
  });

  testWidgets('a map is drawn whole, as a PNG twice as sharp as the map', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    final map = Mindmap(
      nodes: [
        _node('sea', x: -100, y: 0, width: 200, height: 60, text: 'Meer'),
        _node(
          'hills',
          x: 300,
          y: 240,
          width: 160,
          height: 80,
          kind: MindmapKinds.note,
          text: 'Berge',
        ),
      ],
      edges: const [],
    );

    final draw = mindmapDrawingOf(tester.element(find.byType(MindmapScreen)));
    final bytes = await tester.runAsync(
      () => draw((
        title: 'Urlaub',
        map: map,
        members: const {},
        targets: const {},
      )),
    );

    expect(bytes!.sublist(0, _pngMagic.length), equals(_pngMagic));
    // The header's first chunk holds the size, big-endian.
    final header = ByteData.sublistView(bytes);
    const margin = HiwiskiMetrics.mindmapPictureMargin;
    const scale = HiwiskiMetrics.mindmapPictureScale;
    expect(header.getUint32(_widthAt), equals((560 + 2 * margin) * scale));
    expect(header.getUint32(_heightAt), equals((320 + 2 * margin) * scale));
  });

  testWidgets('the pen draws from the moment it touches', (tester) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    await pick(tester, MindmapKeys.drawMenu, MindmapKeys.pen);
    await settle(tester);

    // Ten points: far less than a gesture needs to be recognised as a drag.
    final pen = await tester.startGesture(const Offset(200, 600));
    for (int i = 0; i < 10; i++) {
      await pen.moveBy(const Offset(1, 0));
      await tester.pump();
    }
    await pen.up();
    await settle(tester);

    final rows = await tester.runAsync(() => db.select(db.mindmapNodes).get());
    final stroke = rows!.singleWhere((row) => row.kind == MindmapKinds.drawing);
    expect(stroke.width, closeTo(10 + HiwiskiMetrics.mindmapPenWidths[1], 1));
  });

  testWidgets('two fingers move the map and draw nothing', (tester) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    await pick(tester, MindmapKeys.drawMenu, MindmapKeys.pen);
    await settle(tester);

    // A pinch as a hand makes it: one finger first and moving, the second after, and
    // one lifted before the other, which moves on alone.
    final first = await tester.startGesture(const Offset(300, 500));
    await first.moveBy(const Offset(30, 0));
    await tester.pump();
    final second = await tester.startGesture(const Offset(600, 500));
    for (int i = 0; i < 5; i++) {
      await first.moveBy(const Offset(-10, 0));
      await second.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await first.up();
    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await second.moveBy(const Offset(20, 10));
      await tester.pump();
    }
    await second.up();
    await settle(tester);

    final rows = await tester.runAsync(() => db.select(db.mindmapNodes).get());
    expect(rows!.where((row) => row.kind == MindmapKinds.drawing), isEmpty);
  });

  testWidgets('on a phone every tool is in reach, in the buttons\' place', (
    tester,
  ) async {
    await seed(tester);
    await open(tester, size: const Size(390, 844));
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);

    for (final control in [
      MindmapKeys.addMenu,
      MindmapKeys.drawMenu,
      MindmapKeys.toolsMenu,
      MindmapKeys.undo,
      MindmapKeys.redo,
      MindmapKeys.edit,
    ]) {
      expect(
        find.byKey(control).hitTestable(),
        findsOneWidget,
        reason: '$control',
      );
    }
    for (final (menu, options) in [
      (
        MindmapKeys.addMenu,
        [
          MindmapKeys.tool(MindmapKinds.plain),
          MindmapKeys.tool(MindmapKinds.member),
          MindmapKeys.edgeTool,
        ],
      ),
      (MindmapKeys.drawMenu, [MindmapKeys.pen, MindmapKeys.strokeWidth]),
      (MindmapKeys.toolsMenu, [MindmapKeys.lasso, MindmapKeys.picture]),
    ]) {
      final button = tester.getCenter(find.byKey(menu));
      for (final option in options) {
        await reach(tester, menu, option);
        expect(find.byKey(option).hitTestable(), findsOneWidget);
      }
      // The choices stood where the buttons were; back brings them again.
      expect(find.byKey(menu).hitTestable(), findsNothing);
      await tester.tap(find.byKey(MindmapKeys.closeMenu));
      await settle(tester);
      expect(tester.getCenter(find.byKey(menu)), equals(button));
      expect(find.byKey(MindmapKeys.closeMenu), findsNothing);
    }
  });

  testWidgets('back from the pen puts it down', (tester) async {
    await seed(tester);
    await open(tester, size: const Size(390, 844));
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    await pick(tester, MindmapKeys.drawMenu, MindmapKeys.pen);
    await settle(tester);
    // Chosen, the menu stays.
    expect(find.byKey(MindmapKeys.pen).hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(MindmapKeys.closeMenu));
    await settle(tester);
    // A finger on the map moves it again: nothing is drawn.
    await tester.dragFrom(const Offset(120, 300), const Offset(80, 40));
    await settle(tester);
    final rows = await tester.runAsync(() => db.select(db.mindmapNodes).get());
    expect(rows!.where((row) => row.kind == MindmapKinds.drawing), isEmpty);
  });

  testWidgets('a connection is drawn element by element, on from the last', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    // No dot on an element any more: connecting is a tool of its own, its kinds a
    // level below it — here the arrow.
    expect(find.byKey(ValueKey('$meer-handle')), findsNothing);
    await pick(tester, MindmapKeys.addMenu, MindmapKeys.edgeTool);
    await settle(tester);
    await tester.tap(find.byKey(MindmapKeys.edgeStyleOf(1)));
    await settle(tester);

    Offset centreOf(String text) => tester.getCenter(
      find
          .ancestor(
            of: find.text(text),
            matching: find.byType(MindmapElementView),
          )
          .first,
    );
    // Dragged from one to the other …
    await tester.dragFrom(
      centreOf('Meer'),
      centreOf('Berge') - centreOf('Meer'),
    );
    await settle(tester);
    // … and on from there with a tap: still connecting.
    await tester.tap(find.text('Meer'));
    await settle(tester);

    final edges = await tester.runAsync(() => db.select(db.mindmapEdges).get());
    expect({
      for (final edge in edges!) (edge.fromId, edge.toId),
    }, equals({(meer, berge), (berge, meer)}));
    expect(edges.map((edge) => edge.arrows), everyElement(MindmapArrows.end));

    // Back a level: the tool is put down, and a finger selects again.
    await tester.tap(find.byKey(MindmapKeys.closeMenu));
    await settle(tester);
    await tester.tap(find.text('Berge'));
    await settle(tester);
    expect(find.byKey(MindmapKeys.delete), findsOneWidget);
  });

  testWidgets('a stroke is taken on its line alone, not across its box', (
    tester,
  ) async {
    await seed(tester);
    // A line along the top of a box that holds "Berge" and the canvas below it.
    await tester.runAsync(
      () => container
          .read(mindmapRepositoryProvider)
          .addNode(
            pageId: pageId,
            kind: MindmapKinds.drawing,
            x: 280,
            y: -20,
            width: 200,
            height: 300,
            points: '0,0 10000,0',
            strokeWidth: 4,
          ),
    );
    await open(tester);
    double zoom() =>
        tester.widget<MindmapScene>(find.byType(MindmapScene)).zoom;
    Rect rectOf(String text) => tester.getRect(
      find
          .ancestor(
            of: find.text(text),
            matching: find.byType(MindmapElementView),
          )
          .first,
    );

    // Two taps and a drag on the canvas inside the stroke's box, below "Berge":
    // the map zooms.
    final before = zoom();
    final bergeAt = rectOf('Berge');
    // 160 below it on the map, at the zoom it is shown at.
    final below = bergeAt.bottomCenter + Offset(0, bergeAt.width);
    await tester.tapAt(below);
    await tester.pump(const Duration(milliseconds: 100));
    final gesture = await tester.startGesture(below);
    for (int step = 1; step <= 10; step++) {
      await gesture.moveTo(below + Offset(0, step * 10));
      await tester.pump();
    }
    await gesture.up();
    await settle(tester);
    expect(zoom(), greaterThan(before * 1.5));

    // Connecting to "Berge" under the stroke's box connects "Berge".
    await tester.tap(find.byKey(MindmapKeys.fit));
    await settle(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    await pick(tester, MindmapKeys.addMenu, MindmapKeys.edgeTool);
    await settle(tester);
    await tester.tap(find.byKey(MindmapKeys.edgeStyleOf(1)));
    await settle(tester);
    await tester.dragFrom(
      rectOf('Meer').center,
      rectOf('Berge').center - rectOf('Meer').center,
    );
    await settle(tester);

    final edges = await tester.runAsync(() => db.select(db.mindmapEdges).get());
    expect([
      for (final edge in edges!) (edge.fromId, edge.toId),
    ], equals([(meer, berge)]));
  });

  testWidgets('a connection\'s colour and thickness are chosen before', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    await pick(tester, MindmapKeys.addMenu, MindmapKeys.edgeTool);
    await settle(tester);
    await tester.tap(find.byKey(MindmapKeys.edgeStyleOf(0)));
    await settle(tester);

    await reach(tester, MindmapKeys.addMenu, MindmapKeys.edgeColor);
    await tester.tap(find.byKey(MindmapKeys.edgeColor));
    await settle(tester);
    await tester.tap(find.byKey(MindmapKeys.swatch('RUST')));
    await tester.tap(find.byKey(MindmapKeys.save));
    await settle(tester);
    await reach(tester, MindmapKeys.addMenu, MindmapKeys.edgeWidth);
    await tester.tap(find.byKey(MindmapKeys.edgeWidth));
    await settle(tester);
    await tester.tap(find.byKey(MindmapKeys.choice('4')));
    await settle(tester);

    Offset centreOf(String text) => tester.getCenter(find.text(text));
    await tester.dragFrom(
      centreOf('Meer'),
      centreOf('Berge') - centreOf('Meer'),
    );
    await settle(tester);

    final edge = (await tester.runAsync(
      () => db.select(db.mindmapEdges).get(),
    ))!.single;
    expect(edge.color, equals('RUST'));
    expect(edge.strokeWidth, equals(4));
  });

  testWidgets('a drawn shape keeps its shape and is resized', (tester) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    await pick(tester, MindmapKeys.drawMenu, MindmapKeys.shapes);
    await settle(tester);
    await tester.tap(find.byKey(MindmapKeys.penShape('ellipse')));
    await settle(tester);
    await tester.dragFrom(const Offset(200, 400), const Offset(160, 100));
    await settle(tester);
    final drawn = (await tester.runAsync(
      () => db.select(db.mindmapNodes).get(),
    ))!.where((row) => row.kind == MindmapKinds.drawing).single;
    expect(drawn.shape, equals(MindmapShapes.ellipse));

    // Put down, it is selected — with a corner to resize it by.
    await tester.tap(find.byKey(MindmapKeys.closeMenu));
    await settle(tester);
    await tester.tapAt(const Offset(280, 400));
    await settle(tester);
    expect(find.byKey(ValueKey('${drawn.id}-resize')), findsOneWidget);
  });

  testWidgets('an element is turned by its knob, as one step', (tester) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    await tester.tap(find.text('Meer'));
    await settle(tester);

    final knob = find.byKey(ValueKey('$meer-rotate'));
    expect(knob, findsOneWidget);
    final centre = tester.getCenter(
      find
          .ancestor(
            of: find.text('Meer'),
            matching: find.byType(MindmapElementView),
          )
          .first,
    );
    final from = tester.getCenter(knob);
    // From above the element round to its right: a quarter turn.
    final gesture = await tester.startGesture(from);
    final radius = (from - centre).distance;
    for (int step = 1; step <= 9; step++) {
      final angle = -math.pi / 2 + step * math.pi / 18;
      await gesture.moveTo(
        centre + Offset(math.cos(angle), math.sin(angle)) * radius,
      );
      await tester.pump();
    }
    await gesture.up();
    await settle(tester);

    Future<int?> rotation() async => (await tester.runAsync(
      () => (db.select(
        db.mindmapNodes,
      )..where((row) => row.id.equals(meer))).getSingle(),
    ))!.rotation;
    expect(await rotation(), equals(90));

    await tester.tap(find.byKey(MindmapKeys.undo));
    await settle(tester);
    expect(await rotation(), isNull);
  });

  testWidgets('a new link shows what it points to', (tester) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    await pick(
      tester,
      MindmapKeys.addMenu,
      MindmapKeys.tool(MindmapKinds.link),
    );
    await settle(tester);
    await tester.enterText(find.byKey(CoreKeys.linkSearch), 'Urlaub');
    await settle(tester);
    await tester.tap(
      find
          .descendant(of: find.byType(ListTile), matching: find.text('Urlaub'))
          .first,
    );
    await settle(tester);

    final rows = await tester.runAsync(() => db.select(db.mindmapNodes).get());
    final link = rows!.singleWhere((row) => row.kind == MindmapKinds.link);
    expect(link.linkView, equals(MindmapLinkViews.content));
    expect(
      link.height,
      equals(HiwiskiMetrics.mindmapLinkContentSize.height.round()),
    );
  });

  testWidgets('a shape is drawn in the pen\'s colour as a stroke', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    await pick(tester, MindmapKeys.drawMenu, MindmapKeys.shapes);
    await settle(tester);
    await tester.tap(find.byKey(MindmapKeys.penShape('rectangle')));
    await settle(tester);

    await tester.dragFrom(const Offset(200, 400), const Offset(160, 100));
    await settle(tester);

    final rows = await tester.runAsync(() => db.select(db.mindmapNodes).get());
    final drawn = rows!.where((row) => row.kind == MindmapKinds.drawing).single;
    // Its four corners, each given twice so it stays sharp, and closed.
    expect(drawn.points!.split(' '), hasLength(10));
    // As wide as the drag went, and the pen's width on both sides.
    expect(drawn.width, closeTo(160 + HiwiskiMetrics.mindmapPenWidths[1], 2));
  });

  testWidgets('a finger tapped twice and dragged down zooms in', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    double zoom() =>
        tester.widget<MindmapScene>(find.byType(MindmapScene)).zoom;
    final before = zoom();

    const at = Offset(500, 650);
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 100));
    final gesture = await tester.startGesture(at);
    for (int step = 1; step <= 10; step++) {
      await gesture.moveTo(at + Offset(0, step * 10));
      await tester.pump();
    }
    await gesture.up();
    await settle(tester);

    expect(zoom(), greaterThan(before * 1.5));
  });

  testWidgets('a short snippet is taken a finger\'s width around it', (
    tester,
  ) async {
    await seed(tester);
    // Far off, so that the whole map shown, the snippets are small on screen.
    await tester.runAsync(
      () => container
          .read(mindmapRepositoryProvider)
          .addNode(
            pageId: pageId,
            kind: MindmapKinds.plain,
            x: 2400,
            y: 0,
            width: 160,
            height: 40,
            text: 'Wüste',
          ),
    );
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    final meerBox = tester.getRect(
      find
          .ancestor(
            of: find.text('Meer'),
            matching: find.byType(MindmapElementView),
          )
          .first,
    );
    final zoom = tester.widget<MindmapScene>(find.byType(MindmapScene)).zoom;
    // Far smaller on screen than a finger.
    final height = 40 * zoom;
    expect(height, lessThan(HiwiskiMetrics.minTapTarget / 2));
    // Just above it: outside the snippet, within a finger's width of it.
    await tester.tapAt(meerBox.center - Offset(0, height / 2 + 6));
    await settle(tester);
    expect(find.byKey(MindmapKeys.delete), findsOneWidget);
  });

  testWidgets('a search marks what it found and lists it', (tester) async {
    await seed(tester);
    await open(tester);

    await tester.tap(find.byKey(MindmapKeys.search));
    await settle(tester);
    await tester.enterText(find.byKey(MindmapKeys.searchField), 'mee');
    await settle(tester);

    expect(find.byKey(MindmapKeys.hit(meer)), findsOneWidget);
    expect(find.text('1 match'), findsOneWidget);
  });

  testWidgets('Enter in the search goes from hit to hit, again and again', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.search));
    await settle(tester);
    // "Meer" and "Berge", in that order.
    await tester.enterText(find.byKey(MindmapKeys.searchField), 'e');
    await settle(tester);
    String shown() {
      final results = tester.widget<MindmapResults>(
        find.byType(MindmapResults),
      );
      return results.hits[results.current].id;
    }

    expect(shown(), equals(meer));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    expect(shown(), equals(berge));
    expect(
      tester
          .widget<TextField>(find.byKey(MindmapKeys.searchField))
          .focusNode
          ?.hasFocus,
      isTrue,
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    expect(shown(), equals(meer));
  });

  testWidgets('the hit shown stays the same while the map changes', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.search));
    await settle(tester);
    await tester.enterText(find.byKey(MindmapKeys.searchField), 'e');
    await settle(tester);
    String shown() {
      final results = tester.widget<MindmapResults>(
        find.byType(MindmapResults),
      );
      return results.hits[results.current].id;
    }

    await tester.tap(find.byKey(MindmapKeys.searchNext));
    await settle(tester);
    expect(shown(), equals(berge));
    final maps = container.read(mindmapRepositoryProvider);

    // A hit added before it in the list: still "Berge", not the one now in its
    // place.
    await tester.runAsync(
      () => maps.addNode(
        pageId: pageId,
        kind: MindmapKinds.plain,
        x: 180,
        y: 0,
        width: 80,
        height: 40,
        text: 'See',
      ),
    );
    await settle(tester);
    expect(shown(), equals(berge));

    // The first hit moved: still "Berge", not back to the first.
    await tester.runAsync(() async {
      await maps.changeNode((await maps.node(meer))!, x: 20);
    });
    await settle(tester);
    expect(shown(), equals(berge));

    // A new search begins at its first hit.
    await tester.enterText(find.byKey(MindmapKeys.searchField), 'er');
    await settle(tester);
    expect(shown(), equals(meer));
  });

  testWidgets('while searching, the hit shown is marked, not selected', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    await tester.tap(find.byKey(MindmapKeys.search));
    await settle(tester);
    await tester.enterText(find.byKey(MindmapKeys.searchField), 'Meer');
    await settle(tester);

    final element = find.byWidgetPredicate(
      (widget) => widget is MindmapElementView && widget.node.id == meer,
    );
    // Framed as it is shown, but without grips to resize or turn it.
    expect(tester.widget<MindmapElementView>(element).selected, isTrue);
    expect(find.byKey(ValueKey('$meer-resize')), findsNothing);
    expect(find.byKey(ValueKey('$meer-rotate')), findsNothing);

    // A tap selects it, as any element; it does not open its text.
    await tester.tapAt(tester.getCenter(element));
    await settle(tester);
    expect(find.byKey(MindmapKeys.textField), findsNothing);
    expect(find.byKey(ValueKey('$meer-resize')), findsOneWidget);
  });

  testWidgets('on a phone the search takes the whole line and is ended', (
    tester,
  ) async {
    await seed(tester);
    await open(tester, size: const Size(390, 844));
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);

    await tester.tap(find.byKey(MindmapKeys.search));
    await settle(tester);
    // The editing buttons make room.
    expect(find.byKey(MindmapKeys.undo), findsNothing);
    await tester.enterText(find.byKey(MindmapKeys.searchField), 'Berge');
    await settle(tester);

    // What is typed shows, whole; the field takes most of the line.
    final field = tester.getRect(find.byKey(MindmapKeys.searchField));
    expect(field.width, greaterThan(200));
    final typed = tester.getRect(
      find.descendant(
        of: find.byKey(MindmapKeys.searchField),
        matching: find.byType(EditableText),
      ),
    );
    expect(typed.right, lessThanOrEqualTo(390));
    // The count and the way from hit to hit on a line of their own.
    expect(find.byKey(MindmapKeys.searchCount).hitTestable(), findsOneWidget);
    expect(
      tester.getRect(find.byKey(MindmapKeys.searchCount)).top,
      greaterThan(field.bottom),
    );
    expect(find.byKey(MindmapKeys.searchNext).hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(MindmapKeys.search));
    await settle(tester);
    expect(find.byKey(MindmapKeys.searchField), findsNothing);
    expect(find.byKey(MindmapKeys.searchCount), findsNothing);
    expect(find.byKey(MindmapKeys.undo).hitTestable(), findsOneWidget);
  });

  testWidgets('a map whose page is deleted meanwhile says the page is gone', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);

    await tester.runAsync(() async {
      final wiki = container.read(wikiRepositoryProvider);
      await wiki.deletePage((await wiki.watchPage(pageId).first)!);
    });
    await settle(tester);

    // What any item says once it is gone — not that an element left the map.
    expect(find.text(lookupL(const Locale('en')).stateGone), findsOneWidget);
    expect(find.text('Meer'), findsNothing);
  });

  testWidgets('a new dot shows at once beside the dots already there', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    await pick(tester, MindmapKeys.drawMenu, MindmapKeys.pen);
    await settle(tester);
    final strokes = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is StrokePainter,
    );
    await tester.tapAt(const Offset(200, 600));
    await settle(tester);
    expect(strokes, findsOneWidget);

    // Every dot has the same points in its own box: the first on the map did not
    // make the second count as there before it was.
    await tester.tapAt(const Offset(500, 600));
    await tester.pump();
    expect(strokes, findsNWidgets(2));
    await settle(tester);
    expect(strokes, findsNWidgets(2));
  });

  testWidgets('a map left while it glides lets go of its ticker', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);

    await tester.tap(find.byKey(MindmapKeys.fit));
    await tester.pump(const Duration(milliseconds: 50));
    // Gone mid-glide: the canvas that ticked for it goes first.
    await tester.pumpWidget(const SizedBox.shrink());

    expect(tester.takeException(), isNull);
  });

  testWidgets('a map archived while it is edited is edited no more', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    final element = find
        .ancestor(
          of: find.text('Berge'),
          matching: find.byType(MindmapElementView),
        )
        .first;
    await tester.dragFrom(
      tester.getRect(element).center,
      const Offset(100, 50),
    );
    await settle(tester);
    Future<int> bergeX() async => (await tester.runAsync(
      () => container.read(mindmapRepositoryProvider).node(berge),
    ))!.x;
    final moved = await bergeX();
    expect(moved, isNot(equals(300)));

    await tester.runAsync(() async {
      final wiki = container.read(wikiRepositoryProvider);
      await wiki.archivePage((await wiki.watchPage(pageId).first)!);
    });
    await settle(tester);
    expect(find.byKey(MindmapKeys.addMenu), findsNothing);

    // The move is not taken back …
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await settle(tester);
    expect(await bergeX(), equals(moved));
    // … and a tap reads the snippet instead of writing it.
    await tester.tap(find.text('Berge'));
    await settle(tester);
    expect(find.byKey(MindmapKeys.textField), findsNothing);
  });

  testWidgets('a moved element stays where it was let go', (tester) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    final element = find
        .ancestor(
          of: find.text('Berge'),
          matching: find.byType(MindmapElementView),
        )
        .first;
    final before = tester.getRect(element);

    await tester.dragFrom(before.center, const Offset(100, 50));
    // A frame later, before the database has answered: not back at the old place.
    await tester.pump();
    expect(
      tester.getRect(element).topLeft,
      equals(before.topLeft + const Offset(100, 50)),
    );

    await settle(tester);
    expect(
      tester.getRect(element).topLeft,
      equals(before.topLeft + const Offset(100, 50)),
    );
  });

  testWidgets('a corner dragged zoomed out follows the finger', (tester) async {
    await seed(tester);
    final note = await tester.runAsync(
      () => container
          .read(mindmapRepositoryProvider)
          .addNode(
            pageId: pageId,
            kind: MindmapKinds.note,
            x: 0,
            y: 200,
            width: 200,
            height: 100,
            text: 'Notiz',
          ),
    );
    await open(tester);
    await tester.tap(find.byKey(MindmapKeys.edit));
    await settle(tester);
    final element = find
        .ancestor(
          of: find.text('Notiz'),
          matching: find.byType(MindmapElementView),
        )
        .first;
    await tester.tap(element);
    await settle(tester);

    // Zoomed out to half with Ctrl and the wheel.
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(const Offset(500, 400)));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 347)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    final before = tester.getRect(element);
    expect(before.width, closeTo(100, 1));

    // The grip on the frame's corner, a few points off the element.
    const gap = HiwiskiMetrics.mindmapFrameGap;
    await tester.dragFrom(
      before.bottomRight + const Offset(gap, gap),
      const Offset(50, 20),
    );
    await settle(tester);

    final row = await tester.runAsync(
      () => (db.select(
        db.mindmapNodes,
      )..where((row) => row.id.equals(note!))).getSingle(),
    );
    // 50 and 20 points on screen are 100 and 40 on the map at half the size.
    expect(row!.width, closeTo(300, 2));
    expect(row.height, closeTo(140, 2));
  });

  testWidgets('a map showing its own page shows it once, not without end', (
    tester,
  ) async {
    await seed(tester);
    await tester.runAsync(
      () => container
          .read(mindmapRepositoryProvider)
          .addNode(
            pageId: pageId,
            kind: MindmapKinds.link,
            x: 0,
            y: 200,
            width: 360,
            height: 420,
            target: 'hiwiski://wiki_page/$pageId',
            linkView: MindmapLinkViews.content,
          ),
    );
    await open(tester);

    // On the canvas its content — the page, with the map's picture below it; in
    // that picture the same element by its title only.
    expect(find.byType(MindmapPreviewCard), findsOneWidget);
    expect(find.byType(MindmapLinkContent), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a conflict is decided for its element alone', (tester) async {
    await seed(tester);
    await tester.runAsync(
      () => db
          .into(db.conflicts)
          .insert(
            ConflictRow(
              id: '$meer:${WireFields.text}',
              entityType: EntityTypes.mindmapNode,
              entityId: meer,
              field: WireFields.text,
              mine: '"Meer und Strand"',
              theirs: '"Meer"',
              detectedAt: clock.now(),
            ),
          ),
    );
    await open(tester);

    await tester.tap(find.byKey(MindmapKeys.conflicts));
    await settle(tester);
    // On the map, beside the map's version — no sheet over it — and in the bar
    // below, next to "Meer".
    expect(find.text('Meer und Strand'), findsNWidgets(2));
    expect(find.text('Yours'), findsWidgets);
    await tester.tap(find.byKey(MindmapKeys.keepTheirs));
    await settle(tester);

    final left = await tester.runAsync(() => db.select(db.conflicts).get());
    expect(left, isEmpty);
    expect(find.byKey(MindmapKeys.conflicts), findsNothing);
    expect(find.text('Meer und Strand'), findsNothing);
  });

  testWidgets('a text size of its own that lost is read as its number', (
    tester,
  ) async {
    await seed(tester);
    await tester.runAsync(
      () => db
          .into(db.conflicts)
          .insert(
            ConflictRow(
              id: '$meer:${WireFields.textSize}',
              entityType: EntityTypes.mindmapNode,
              entityId: meer,
              field: WireFields.textSize,
              mine: '"24"',
              theirs: '"${MindmapTextSizes.large}"',
              detectedAt: clock.now(),
            ),
          ),
    );
    await open(tester);

    await tester.tap(find.byKey(MindmapKeys.conflicts));
    await settle(tester);
    final bar = find.byType(MindmapConflictBar);
    expect(find.descendant(of: bar, matching: find.text('24')), findsOneWidget);
    expect(
      find.descendant(of: bar, matching: find.text('Large')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bar, matching: find.text('Medium')),
      findsNothing,
    );
  });

  testWidgets('a position that lost is one conflict, shown on the map', (
    tester,
  ) async {
    await seed(tester);
    await tester.runAsync(() async {
      for (final (field, mine, theirs) in [
        (WireFields.x, '300', '0'),
        (WireFields.y, '120', '0'),
      ]) {
        await db
            .into(db.conflicts)
            .insert(
              ConflictRow(
                id: '$meer:$field',
                entityType: EntityTypes.mindmapNode,
                entityId: meer,
                field: field,
                mine: mine,
                theirs: theirs,
                detectedAt: clock.now(),
              ),
            );
      }
    });
    await open(tester);

    await tester.tap(find.byKey(MindmapKeys.conflicts));
    await settle(tester);
    expect(find.text('On the map: Position'), findsOneWidget);
    // The map's version where it is, this device's where it was moved to.
    expect(find.text('Meer'), findsNWidgets(2));
    // Both of the position's fields go with the one decision.
    await tester.tap(find.byKey(MindmapKeys.keepTheirs));
    await settle(tester);

    final left = await tester.runAsync(() => db.select(db.conflicts).get());
    expect(left, isEmpty);
  });

  testWidgets('the banner names a moved element once and shows it on the map', (
    tester,
  ) async {
    await seed(tester);
    await tester.runAsync(() async {
      for (final (field, mine) in [
        (WireFields.x, '300'),
        (WireFields.y, '120'),
      ]) {
        await db
            .into(db.conflicts)
            .insert(
              ConflictRow(
                id: '$meer:$field',
                entityType: EntityTypes.mindmapNode,
                entityId: meer,
                field: field,
                mine: mine,
                theirs: '0',
                detectedAt: clock.now(),
              ),
            );
      }
    });
    container.dispose();
    container = await containerFor(banner: true);
    await open(tester);

    expect(
      find.text('"Position" was changed elsewhere at the same time.'),
      findsOneWidget,
    );
    await tester.tap(find.text('View'));
    await settle(tester);

    // Both values of the position as one — "300, 120" — each side marked against
    // the other's "0, 0".
    final values = [
      for (final widget in tester.widgetList<SelectableText>(
        find.byType(SelectableText),
      ))
        ?widget.textSpan?.toPlainText(),
    ];
    expect(values, equals(['3000, 1200', '0300, 0120']));
    await tester.tap(find.text('Show in mind map'));
    await settle(tester);

    // Decided on this map, not on a second one opened over it.
    expect(find.byType(MindmapScreen), findsOneWidget);
    expect(find.text('On the map: Position'), findsOneWidget);
  });

  testWidgets(
    'the banner reads a size as width by height, whichever came first',
    (tester) async {
      await seed(tester);
      await tester.runAsync(() async {
        // The height's conflict found before the width's.
        for (final (field, mine, theirs, at) in [
          (WireFields.height, '90', '40', DateTime(2026, 11, 20)),
          (WireFields.width, '200', '160', DateTime(2026, 11, 21)),
        ]) {
          await db
              .into(db.conflicts)
              .insert(
                ConflictRow(
                  id: '$meer:$field',
                  entityType: EntityTypes.mindmapNode,
                  entityId: meer,
                  field: field,
                  mine: mine,
                  theirs: theirs,
                  detectedAt: at,
                ),
              );
        }
      });
      container.dispose();
      container = await containerFor(banner: true);
      await open(tester);

      await tester.tap(find.text('View'));
      await settle(tester);
      final values = [
        for (final widget in tester.widgetList<SelectableText>(
          find.byType(SelectableText),
        ))
          ?widget.textSpan?.toPlainText(),
      ];
      expect(values, hasLength(2));
      for (final value in values) {
        expect(value, contains(' × '));
        expect(value, isNot(contains(', ')));
      }
    },
  );

  testWidgets('the banner names whom a member element showed on each side', (
    tester,
  ) async {
    await seed(tester);
    await tester.runAsync(() async {
      final member = await container
          .read(mindmapRepositoryProvider)
          .addNode(
            pageId: pageId,
            kind: MindmapKinds.member,
            x: 0,
            y: 200,
            width: 80,
            height: 80,
            target: memberAddressOf('anna'),
          );
      await db
          .into(db.conflicts)
          .insert(
            ConflictRow(
              id: '$member:${WireFields.target}',
              entityType: EntityTypes.mindmapNode,
              entityId: member,
              field: WireFields.target,
              mine: '"${memberAddressOf('ben')}"',
              theirs: '"${memberAddressOf('anna')}"',
              detectedAt: clock.now(),
            ),
          );
    });
    container.dispose();
    container = await containerFor(banner: true, family: _Family());
    await open(tester);

    await tester.tap(find.text('View'));
    await settle(tester);
    final values = [
      for (final widget in tester.widgetList<SelectableText>(
        find.byType(SelectableText),
      ))
        ?widget.textSpan?.toPlainText(),
    ];
    // Theirs, then this device's — each marked against the other.
    expect(values, equals(['BenAnna', 'AnnaBen']));
  });
}

/// Taps [option] of [menu] in the corner: the menu opened unless it is — on a phone,
/// back from another one first — and the ring turned until the option is in reach,
/// as a finger does.
Future<void> pick(
  WidgetTester tester,
  ValueKey<String> menu,
  ValueKey<String> option,
) async {
  await reach(tester, menu, option);
  await tester.tap(find.byKey(option));
}

/// Brings [option] of [menu] into reach in the corner (see [pick]).
Future<void> reach(
  WidgetTester tester,
  ValueKey<String> menu,
  ValueKey<String> option,
) async {
  // Something selected holds the corner: let go of it first.
  if (find.byKey(option).evaluate().isEmpty &&
      find.byKey(MindmapKeys.release).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(MindmapKeys.release));
    await settle(tester);
  }
  final corner = tester.widget<MindmapCorner>(find.byType(MindmapCorner));
  final open = switch (corner.open) {
    final index? => corner.menus[index].key,
    null => null,
  };
  if (open != menu) {
    // On a phone another menu's choices stand where its button was: back first.
    if (find.byKey(menu).hitTestable().evaluate().isEmpty &&
        find.byKey(MindmapKeys.closeMenu).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(MindmapKeys.closeMenu));
      await settle(tester);
    }
    await tester.tap(find.byKey(menu));
    await settle(tester);
  }
  for (
    int turn = 0;
    find.byKey(option).hitTestable().evaluate().isEmpty;
    turn++
  ) {
    if (turn > _turnsAtMost) fail('$option is not on the ring');
    await turnCorner(tester);
  }
}

/// A finger along the corner's open ring — right over its choices — from the top
/// towards the left edge and a little past it, below the ring's middle: the later
/// choices come into view.
Future<void> turnCorner(WidgetTester tester) async {
  final corner = find.byType(MindmapCorner);
  // The rings go round the screen's corner — the corner's box's own.
  final centre = tester.getRect(corner).bottomRight;
  final ring = mindmapCornerLayout(
    compact: tester.widget<MindmapCorner>(corner).compact,
    safe: MediaQuery.paddingOf(tester.element(corner)),
  ).options;
  Offset at(double angle) =>
      centre + Offset(math.cos(angle), math.sin(angle)) * ring;
  // From just inside the quarter's top end — to its right lies the screen's edge.
  final gesture = await tester.startGesture(at(-math.pi / 2 - 0.2));
  for (
    double angle = -math.pi / 2 - 0.2;
    angle > -math.pi - 0.25;
    angle -= 0.1
  ) {
    await gesture.moveTo(at(angle));
  }
  await gesture.up();
  await settle(tester);
}

const _turnsAtMost = 5;

/// Lets the database's streams and the canvas's first fit come through.
Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
}

class _NoSync implements SyncTrigger {
  @override
  Future<void> syncNow() async {}
}

/// Anna and Ben.
class _Family extends NoFamily {
  @override
  Stream<List<Member>> watchMembers() => .value(const [
    Member(
      id: 'anna',
      username: 'anna',
      displayName: 'Anna',
      isAdmin: true,
      colorToken: .blue,
    ),
    Member(
      id: 'ben',
      username: 'ben',
      displayName: 'Ben',
      isAdmin: false,
      colorToken: .green,
    ),
  ]);
}

MindmapNode _node(
  String id, {
  required int x,
  required int y,
  required int width,
  required int height,
  required String text,
  String kind = MindmapKinds.plain,
}) => .new(
  id: id,
  ownerId: 'anna',
  version: 1,
  pageId: 'page',
  kind: kind,
  x: x,
  y: y,
  width: width,
  height: height,
  layer: 1,
  text: text,
);

const _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const _widthAt = 16;
const _heightAt = 20;
