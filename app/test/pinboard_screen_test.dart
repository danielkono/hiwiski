import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
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
import 'package:hiwiski/core/theme/hiwiski_symbols.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/sync/local_writes.dart';
import 'package:hiwiski/core/sync/outbox.dart';
import 'package:hiwiski/core/sync/sync_engine.dart';
import 'package:hiwiski/core/sync/sync_status.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/core/ui/flowing_text.dart';
import 'package:hiwiski/core/ui/ui_keys.dart';
import 'package:hiwiski/domain/calendar/event_draft.dart';
import 'package:hiwiski/domain/wiki/pinboard.dart';
import 'package:hiwiski/domain/wiki/pinboard_kinds.dart';
import 'package:hiwiski/features/wiki/pinboard/view/pinboard_conflict_bar.dart';
import 'package:hiwiski/features/wiki/pinboard/view/pinboard_corner.dart';
import 'package:hiwiski/features/wiki/pinboard/view/pinboard_keys.dart';
import 'package:hiwiski/features/wiki/pinboard/view/pinboard_results.dart';
import 'package:hiwiski/features/wiki/pinboard/view/pinboard_screen.dart';
import 'package:hiwiski/features/wiki/page/view/pinboard/pinboard_preview_card.dart';
import 'package:hiwiski/features/wiki/view/pinboard/pinboard_link.dart';
import 'package:hiwiski/features/wiki/view/pinboard/pinboard_note.dart';
import 'package:hiwiski/features/wiki/view/pinboard/pinboard_picture.dart';
import 'package:hiwiski/features/wiki/view/pinboard/pinboard_scene.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// The pinboard full screen: read and searched by everyone who sees the page,
/// edited with "Edit" — each change written at once — and a conflict decided for the
/// one element it is about.
/// What shows [text]: a `Text`, or a note saying it — a note's lines are drawn one
/// by one, not as a `Text`.
Finder showing(String text) => find.byWidgetPredicate(
  (widget) => switch (widget) {
    PinboardNote(:final node) => node.text == text,
    Text(:final data, :final textSpan) =>
      (data ?? textSpan?.toPlainText()) == text,
    _ => false,
  },
);

/// The lines of the note on the map, where they stand on the screen.
List<({Rect rect, String text})> noteLines(WidgetTester tester) {
  final render = tester.renderObject<RenderFlowingText>(
    find.descendant(
      of: find.byType(PinboardNote),
      matching: find.byType(FlowingText),
    ),
  );
  final toScreen = render.getTransformTo(null);
  return [
    for (final line in render.lines)
      (rect: MatrixUtils.transformRect(toScreen, line.rect), text: line.text),
  ];
}

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
          home: PinboardScreen(pageId: pageId),
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
        .createPage(title: 'Urlaub', kind: PageKinds.pinboard);
    final maps = container.read(pinboardRepositoryProvider);
    meer = await maps.addNode(
      pageId: pageId,
      kind: PinboardKinds.plain,
      x: 0,
      y: 0,
      width: 160,
      height: 40,
      text: 'Meer',
    );
    berge = await maps.addNode(
      pageId: pageId,
      kind: PinboardKinds.plain,
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
    expect(find.byKey(PinboardKeys.tool(PinboardKinds.plain)), findsNothing);

    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    // Written where it lands, no sheet over the map; kept once it is left.
    await pick(
      tester,
      PinboardKeys.addMenu,
      PinboardKeys.tool(PinboardKinds.plain),
    );
    await settle(tester);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.enterText(find.byKey(PinboardKeys.textField), 'Wüste');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    final rows = await tester.runAsync(() => db.select(db.pinboardNodes).get());
    expect(
      rows!.map((row) => row.body),
      containsAll(['Meer', 'Berge', 'Wüste']),
    );
    expect(find.text('Wüste'), findsOneWidget);
    // Just as large as its one word.
    final placed = rows.firstWhere((row) => row.body == 'Wüste');
    expect(placed.width, lessThan(HiwiskiMetrics.pinboardPlainWrap / 2));
    // Placed and selected: what can be done with it shows.
    expect(find.byKey(PinboardKeys.delete), findsOneWidget);
  });

  testWidgets('what is typed stays in view, word for word', (tester) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    await pick(
      tester,
      PinboardKeys.addMenu,
      PinboardKeys.tool(PinboardKinds.plain),
    );
    await settle(tester);

    for (final text in ['Hallo', 'Hallo Welt', 'Hallo Welt und Meer']) {
      await tester.enterText(find.byKey(PinboardKeys.textField), text);
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
              matching: find.byType(PinboardElementView),
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
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    // Selected with a tap, written with the next.
    await tester.tap(find.text('Meer'));
    await settle(tester);
    await tester.tap(find.text('Meer'));
    await settle(tester);

    await tester.enterText(
      find.byKey(PinboardKeys.textField),
      'Meer und Strand',
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    Future<String?> textOf(String id) async => (await tester.runAsync(
      () => (db.select(
        db.pinboardNodes,
      )..where((row) => row.id.equals(id))).getSingle(),
    ))?.body;
    expect(await textOf(meer), equals('Meer und Strand'));
    expect(find.text('Meer und Strand'), findsOneWidget);

    await tester.tap(find.text('Meer und Strand'));
    await settle(tester);
    await tester.enterText(find.byKey(PinboardKeys.textField), '');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    final left = await tester.runAsync(
      () => (db.select(
        db.pinboardNodes,
      )..where((row) => row.id.equals(meer))).getSingle(),
    );
    expect(left?.deletedAt, isNotNull);
  });

  testWidgets('on a phone, what is typed is kept when another snippet starts', (
    tester,
  ) async {
    await seed(tester);
    await open(tester, size: const Size(390, 844));
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    Future<List<String>> texts() async => [
      for (final row in (await tester.runAsync(
        () => db.select(db.pinboardNodes).get(),
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
      find.byKey(PinboardKeys.textField),
      'Meer und Strand',
    );
    await tester.pump();
    await tester.tap(find.byKey(PinboardKeys.editContent));
    await settle(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(PinboardKeys.textField))
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
      PinboardKeys.addMenu,
      PinboardKeys.tool(PinboardKinds.plain),
    );
    await settle(tester);
    await tester.enterText(find.byKey(PinboardKeys.textField), 'Hallo');
    await tester.pump();
    await pick(
      tester,
      PinboardKeys.addMenu,
      PinboardKeys.tool(PinboardKinds.plain),
    );
    await settle(tester);
    await tester.enterText(find.byKey(PinboardKeys.textField), 'Welt');
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
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);

    await pick(
      tester,
      PinboardKeys.addMenu,
      PinboardKeys.tool(PinboardKinds.member),
    );
    await settle(tester);
    await tester.tap(find.byKey(PinboardKeys.member('ben')));
    await settle(tester);

    final rows = await tester.runAsync(() => db.select(db.pinboardNodes).get());
    final placed = rows!.firstWhere((row) => row.kind == PinboardKinds.member);
    expect(placed.target, equals('hiwiski://member/ben'));
    expect(placed.width, equals(placed.height));
    expect(
      tester
          .widgetList<MemberAvatar>(find.byType(MemberAvatar))
          .map((avatar) => avatar.displayName),
      equals(['Ben']),
    );

    // Resized, the next one placed is as large.
    final zoom = tester.widget<PinboardScene>(find.byType(PinboardScene)).zoom;
    await tester.drag(
      find.byKey(ValueKey('${placed.id}-resize')),
      Offset(60 * zoom, 60 * zoom),
    );
    await settle(tester);
    final resized = (await tester.runAsync(
      () => (db.select(
        db.pinboardNodes,
      )..where((row) => row.id.equals(placed.id))).getSingle(),
    ))!;
    expect(resized.width, greaterThan(placed.width));
    await pick(
      tester,
      PinboardKeys.addMenu,
      PinboardKeys.tool(PinboardKinds.member),
    );
    await settle(tester);
    await tester.tap(find.byKey(PinboardKeys.member('ben')));
    await settle(tester);
    final again =
        (await tester.runAsync(() => db.select(db.pinboardNodes).get()))!
            .where(
              (row) => row.kind == PinboardKinds.member && row.id != placed.id,
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
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    final guides = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          '${widget.painter.runtimeType}' == '_GuidesPainter',
    );
    Future<int> bergeTop() async => (await tester.runAsync(
      () => (db.select(
        db.pinboardNodes,
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
    await pick(tester, PinboardKeys.toolsMenu, PinboardKeys.snap);
    await settle(tester);
    snapping = false;
    await nudge();
    final zoom = tester.widget<PinboardScene>(find.byType(PinboardScene)).zoom;
    expect(await bergeTop(), equals((4 / zoom).round()));
  });

  testWidgets('a resized element takes another\'s height', (tester) async {
    await seed(tester);
    // Notes: a snippet's height is its text's.
    final small = await tester.runAsync(() async {
      final maps = container.read(pinboardRepositoryProvider);
      await maps.addNode(
        pageId: pageId,
        kind: PinboardKinds.note,
        x: 600,
        y: 300,
        width: 160,
        height: 80,
        text: 'Wüste',
      );
      return maps.addNode(
        pageId: pageId,
        kind: PinboardKinds.note,
        x: 0,
        y: 200,
        width: 160,
        height: 40,
        text: 'Steppe',
      );
    });
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    await tester.tap(showing('Steppe'));
    await settle(tester);
    final zoom = tester.widget<PinboardScene>(find.byType(PinboardScene)).zoom;

    // To 3 short of the other note's height: it takes it.
    await tester.drag(
      find.byKey(ValueKey('$small-resize')),
      Offset(0, 37 * zoom),
    );
    await settle(tester);

    final row = await tester.runAsync(
      () => (db.select(
        db.pinboardNodes,
      )..where((row) => row.id.equals(small!))).getSingle(),
    );
    expect(row!.height, equals(80));
  });

  testWidgets('a group is aligned, lined up and made one height, each one '
      'step', (tester) async {
    await seed(tester);
    final notes = await tester.runAsync(() async {
      final maps = container.read(pinboardRepositoryProvider);
      return [
        await maps.addNode(
          pageId: pageId,
          kind: PinboardKinds.note,
          x: 0,
          y: 200,
          width: 200,
          height: 100,
          text: 'Erste',
        ),
        await maps.addNode(
          pageId: pageId,
          kind: PinboardKinds.note,
          x: 300,
          y: 250,
          width: 120,
          height: 60,
          text: 'Zweite',
        ),
      ];
    });
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    Future<List<Rect>> boxes() async => [
      for (final id in notes!)
        switch (await tester.runAsync(
          () => (db.select(
            db.pinboardNodes,
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
            of: showing(text),
            matching: find.byType(PinboardElementView),
          )
          .first,
    );
    final area = around('Erste').expandToInclude(around('Zweite')).inflate(16);
    await pick(tester, PinboardKeys.toolsMenu, PinboardKeys.rectangle);
    await settle(tester);
    await tester.dragFrom(area.topLeft, area.bottomRight - area.topLeft);
    await settle(tester);

    Future<void> command(String name) async {
      if (find.byKey(PinboardKeys.align).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(PinboardKeys.align));
        await settle(tester);
      }
      for (
        int turn = 0;
        find.byKey(PinboardKeys.arrange(name)).hitTestable().evaluate().isEmpty;
        turn++
      ) {
        if (turn > 5) fail('$name is not on the ring');
        await turnCorner(tester);
      }
      await tester.tap(find.byKey(PinboardKeys.arrange(name)));
      await settle(tester);
    }

    final before = await boxes();
    await command('left');
    expect((await boxes()).map((box) => box.left), everyElement(0));
    await tester.tap(find.byKey(PinboardKeys.undo));
    await settle(tester);
    expect(await boxes(), equals(before));

    // Side by side, a gap apart, on one middle — the two stood apart and askew.
    await command('sideBySide');
    final [first, second] = await boxes();
    expect(
      second.left - first.right,
      closeTo(HiwiskiMetrics.pinboardRowGap, 1),
    );
    expect(second.center.dy, closeTo(first.center.dy, 1));
    await tester.tap(find.byKey(PinboardKeys.undo));
    await settle(tester);
    expect(await boxes(), equals(before));

    await command('sameHeight');
    final sized = await boxes();
    expect(sized.map((box) => box.height), everyElement(100));
    // The height alone: the second keeps its width.
    expect(sized[1].width, equals(120));
    await tester.tap(find.byKey(PinboardKeys.undo));
    await settle(tester);
    expect(await boxes(), equals(before));
  });

  testWidgets('with the grid on, a moved element lands on it', (tester) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    await pick(tester, PinboardKeys.toolsMenu, PinboardKeys.grid);
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
        db.pinboardNodes,
      )..where((row) => row.id.equals(berge))).getSingle(),
    );
    const grid = HiwiskiMetrics.pinboardGrid;
    expect(row!.x % grid, equals(0));
    expect(row.y % grid, equals(0));

    // Snapping off is off for the grid too: it stays, only to be seen.
    await pick(tester, PinboardKeys.toolsMenu, PinboardKeys.snap);
    await settle(tester);
    final zoom = tester.widget<PinboardScene>(find.byType(PinboardScene)).zoom;
    await tester.drag(find.text('Berge'), const Offset(37, 53));
    await settle(tester);
    final moved = await tester.runAsync(
      () => (db.select(
        db.pinboardNodes,
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
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    await pick(tester, PinboardKeys.drawMenu, PinboardKeys.pen);
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
    Future<List<PinboardNodeRow>> strokes() async => [
      for (final row in (await tester.runAsync(
        () => db.select(db.pinboardNodes).get(),
      ))!)
        if (row.kind == PinboardKinds.drawing) row,
    ];
    final drawn = (await strokes()).single;
    expect(drawn.points, isNotNull);
    expect(drawn.deletedAt, isNull);
    // As wide as the line went, and the pen's width on both sides.
    expect(drawn.width, closeTo(200 + HiwiskiMetrics.pinboardPenWidths[1], 2));

    // Put down, the stroke is selected on its line — with neither a dot to connect
    // it nor a corner to resize it.
    await pick(tester, PinboardKeys.drawMenu, PinboardKeys.pen);
    await settle(tester);
    await pick(tester, PinboardKeys.toolsMenu, PinboardKeys.drawings);
    await settle(tester);
    expect(drawnStrokes, findsNothing);
    await pick(tester, PinboardKeys.toolsMenu, PinboardKeys.drawings);
    await settle(tester);
    expect(drawnStrokes, findsOneWidget);
    await tester.tapAt(const Offset(300, 600));
    await settle(tester);
    expect(find.byKey(PinboardKeys.delete), findsOneWidget);
    expect(find.byKey(ValueKey('${drawn.id}-handle')), findsNothing);
    expect(find.byKey(ValueKey('${drawn.id}-resize')), findsNothing);

    // The eraser across it, top to bottom: gone with the swipe. Let go of the
    // stroke first: while something is selected, the corner holds its choices.
    await tester.tap(find.byKey(PinboardKeys.release));
    await settle(tester);
    await pick(tester, PinboardKeys.drawMenu, PinboardKeys.eraser);
    await settle(tester);
    await tester.dragFrom(const Offset(300, 540), const Offset(0, 120));
    await settle(tester);
    expect((await strokes()).single.deletedAt, isNotNull);

    // And back with "Undo".
    await tester.tap(find.byKey(PinboardKeys.undo));
    await settle(tester);
    expect((await strokes()).single.deletedAt, isNull);
  });

  group('Undo takes back what is seen, not only what is stored', () {
    final strokesSeen = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is StrokePainter,
    );
    Future<List<PinboardNodeRow>> living(WidgetTester tester) async => [
      for (final row in (await tester.runAsync(
        () => db.select(db.pinboardNodes).get(),
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
      await step(tester, PinboardKeys.edit);
      await pick(tester, PinboardKeys.drawMenu, PinboardKeys.pen);
      await settle(tester);
      await tester.dragFrom(const Offset(200, 500), const Offset(200, 0));
      await settle(tester);
      await tester.dragFrom(const Offset(200, 650), const Offset(200, 0));
      await settle(tester);
      expect(strokesSeen, findsNWidgets(2));

      // The last drawn first — and gone from sight, not only from the map.
      await step(tester, PinboardKeys.undo);
      expect(strokesSeen, findsOneWidget);
      final left = [
        for (final row in await living(tester))
          if (row.kind == PinboardKinds.drawing) row,
      ];
      expect(left.single.y, lessThan(550));
      await step(tester, PinboardKeys.undo);
      expect(strokesSeen, findsNothing);

      await step(tester, PinboardKeys.redo);
      expect(strokesSeen, findsOneWidget);
      await step(tester, PinboardKeys.redo);
      expect(strokesSeen, findsNWidgets(2));
    });

    testWidgets('a snippet written in place, new and rewritten', (
      tester,
    ) async {
      await seed(tester);
      await open(tester);
      await step(tester, PinboardKeys.edit);
      await pick(
        tester,
        PinboardKeys.addMenu,
        PinboardKeys.tool(PinboardKinds.plain),
      );
      await settle(tester);
      await tester.enterText(find.byKey(PinboardKeys.textField), 'Wüste');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.text('Wüste'), findsOneWidget);

      await step(tester, PinboardKeys.undo);
      expect(find.text('Wüste'), findsNothing);
      await step(tester, PinboardKeys.redo);
      expect(find.text('Wüste'), findsOneWidget);

      // Rewritten, and taken back: the old words again.
      await tester.tap(find.text('Meer'));
      await settle(tester);
      await tester.tap(find.text('Meer'));
      await settle(tester);
      await tester.enterText(find.byKey(PinboardKeys.textField), 'Ozean');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.text('Ozean'), findsOneWidget);
      await step(tester, PinboardKeys.undo);
      expect(find.text('Ozean'), findsNothing);
      expect(find.text('Meer'), findsOneWidget);
    });

    testWidgets('a move, taken back at once', (tester) async {
      await seed(tester);
      await open(tester);
      await step(tester, PinboardKeys.edit);
      final element = find
          .ancestor(
            of: find.text('Berge'),
            matching: find.byType(PinboardElementView),
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
      await step(tester, PinboardKeys.undo);
      expect(tester.getRect(element).topLeft, equals(before.topLeft));
    });
  });

  testWidgets('the corner turns to show the choices that do not fit', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    // A stroke, so that the tools hold all they can: six choices.
    await pick(tester, PinboardKeys.drawMenu, PinboardKeys.pen);
    await settle(tester);
    await tester.dragFrom(const Offset(300, 300), const Offset(80, 40));
    await settle(tester);
    await pick(tester, PinboardKeys.drawMenu, PinboardKeys.pen);
    await settle(tester);

    await tester.tap(find.byKey(PinboardKeys.toolsMenu));
    await settle(tester);
    expect(find.byKey(PinboardKeys.select), findsOneWidget);
    expect(find.byKey(PinboardKeys.picture), findsNothing);

    // Past the left edge too: there the angle jumps from -π to π, and the turn
    // must not jump with it.
    await turnCorner(tester);
    expect(find.byKey(PinboardKeys.picture).hitTestable(), findsOneWidget);
    expect(find.byKey(PinboardKeys.select), findsNothing);
  });

  testWidgets('the corner shows the first choices of what is selected next', (
    tester,
  ) async {
    List<PinboardCornerOption> choices(String name, int count) => [
      for (int i = 0; i < count; i++)
        PinboardCornerOption(
          key: ValueKey('$name$i'),
          icon: Icons.edit,
          label: '$name$i',
          onTap: () {},
        ),
    ];
    Future<void> show(List<PinboardCornerOption> selection) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: HiwiskiTheme.light(),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: PinboardCorner(
                    menus: const [],
                    open: null,
                    onOpen: (_) {},
                    compact: false,
                    backKey: PinboardKeys.closeMenu,
                    backLabel: 'Back',
                    onBack: () {},
                    selection: selection,
                    onRelease: () {},
                    releaseKey: PinboardKeys.release,
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
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    PinboardElementView viewOf(String text) => tester.widget(
      find
          .ancestor(
            of: find.text(text),
            matching: find.byType(PinboardElementView),
          )
          .first,
    );
    Rect rectOf(String text) => tester.getRect(
      find
          .ancestor(
            of: find.text(text),
            matching: find.byType(PinboardElementView),
          )
          .first,
    );
    final meerBefore = rectOf('Meer');
    final bergeBefore = rectOf('Berge');

    // A rectangle round both.
    await pick(tester, PinboardKeys.toolsMenu, PinboardKeys.rectangle);
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
    await tester.tap(find.byKey(PinboardKeys.delete));
    await settle(tester);
    expect(find.text('Meer'), findsNothing);
    expect(find.text('Berge'), findsNothing);
    await tester.tap(find.byKey(PinboardKeys.undo));
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
          .read(pinboardRepositoryProvider)
          .addNode(
            pageId: pageId,
            kind: PinboardKinds.drawing,
            x: 180,
            y: 0,
            width: 100,
            height: 40,
            look: {
              WireFields.points: '0,5000 10000,5000',
              WireFields.strokeWidth: 4,
            },
          ),
    ))!;
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    final meerAt = tester.getRect(find.text('Meer'));
    final bergeAt = tester.getRect(find.text('Berge'));

    // The strokes hidden, a rectangle round everything — and what it took deleted.
    await pick(tester, PinboardKeys.toolsMenu, PinboardKeys.drawings);
    await settle(tester);
    // Closed and opened again: the ring turned to the switch starts at its first
    // choice once more.
    await tester.tap(find.byKey(PinboardKeys.toolsMenu));
    await settle(tester);
    await pick(tester, PinboardKeys.toolsMenu, PinboardKeys.rectangle);
    await settle(tester);
    final around = meerAt.expandToInclude(bergeAt).inflate(40);
    await tester.dragFrom(around.topLeft, around.bottomRight - around.topLeft);
    await settle(tester);
    await tester.tap(find.byKey(PinboardKeys.delete));
    await settle(tester);

    Future<PinboardNodeRow> row(String id) async => (await tester.runAsync(
      () => (db.select(
        db.pinboardNodes,
      )..where((row) => row.id.equals(id))).getSingle(),
    ))!;
    expect((await row(meer)).deletedAt, isNotNull);
    expect((await row(stroke)).deletedAt, isNull);
  });

  testWidgets('a text size of its own, as a number', (tester) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    await tester.tap(find.text('Meer'));
    await settle(tester);

    await tester.tap(find.byKey(PinboardKeys.textSize));
    await settle(tester);
    await tester.enterText(find.byKey(PinboardKeys.ownNumber), '30');
    await tester.pump();
    await tester.tap(find.byKey(PinboardKeys.ownApply));
    await settle(tester);

    final row = await tester.runAsync(
      () => (db.select(
        db.pinboardNodes,
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
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    await tester.tap(find.text('Meer'));
    await settle(tester);
    await tester.tap(find.text('Meer'));
    await settle(tester);
    const text = 'Meer und Strand und Dünen am Abend';
    await tester.enterText(find.byKey(PinboardKeys.textField), text);
    await tester.pump();
    Future<PinboardNodeRow> row() async => (await tester.runAsync(
      () => (db.select(
        db.pinboardNodes,
      )..where((row) => row.id.equals(meer))).getSingle(),
    ))!;

    // The sheet takes the field's focus: what is typed is written first.
    await tester.tap(find.byKey(PinboardKeys.textSize));
    await settle(tester);
    final written = await row();
    expect(written.body, equals(text));
    await tester.enterText(find.byKey(PinboardKeys.ownNumber), '30');
    await tester.pump();
    await tester.tap(find.byKey(PinboardKeys.ownApply));
    await settle(tester);

    final box = PinboardElementView.plainBoxOf(
      tester.element(find.byType(PinboardScreen)),
      text,
      '30',
      maxWidth: math.max(
        written.width.toDouble(),
        HiwiskiMetrics.pinboardPlainWrap,
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
    final map = Pinboard(
      nodes: [
        _node('sea', x: -100, y: 0, width: 200, height: 60, text: 'Meer'),
        _node(
          'hills',
          x: 300,
          y: 240,
          width: 160,
          height: 80,
          kind: PinboardKinds.note,
          text: 'Berge',
        ),
      ],
      edges: const [],
    );

    final draw = pinboardDrawingOf(tester.element(find.byType(PinboardScreen)));
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
    const margin = HiwiskiMetrics.pinboardPictureMargin;
    const scale = HiwiskiMetrics.pinboardPictureScale;
    expect(header.getUint32(_widthAt), equals((560 + 2 * margin) * scale));
    expect(header.getUint32(_heightAt), equals((320 + 2 * margin) * scale));
  });

  testWidgets('the pen draws from the moment it touches', (tester) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    await pick(tester, PinboardKeys.drawMenu, PinboardKeys.pen);
    await settle(tester);

    // Ten points: far less than a gesture needs to be recognised as a drag.
    final pen = await tester.startGesture(const Offset(200, 600));
    for (int i = 0; i < 10; i++) {
      await pen.moveBy(const Offset(1, 0));
      await tester.pump();
    }
    await pen.up();
    await settle(tester);

    final rows = await tester.runAsync(() => db.select(db.pinboardNodes).get());
    final stroke = rows!.singleWhere(
      (row) => row.kind == PinboardKinds.drawing,
    );
    expect(stroke.width, closeTo(10 + HiwiskiMetrics.pinboardPenWidths[1], 1));
  });

  testWidgets('two fingers move the map and draw nothing', (tester) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    await pick(tester, PinboardKeys.drawMenu, PinboardKeys.pen);
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

    final rows = await tester.runAsync(() => db.select(db.pinboardNodes).get());
    expect(rows!.where((row) => row.kind == PinboardKinds.drawing), isEmpty);
  });

  testWidgets('on a phone every tool is in reach, in the buttons\' place', (
    tester,
  ) async {
    await seed(tester);
    await open(tester, size: const Size(390, 844));
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);

    for (final control in [
      PinboardKeys.addMenu,
      PinboardKeys.drawMenu,
      PinboardKeys.toolsMenu,
      PinboardKeys.undo,
      PinboardKeys.redo,
      PinboardKeys.edit,
    ]) {
      expect(
        find.byKey(control).hitTestable(),
        findsOneWidget,
        reason: '$control',
      );
    }
    for (final (menu, options) in [
      (
        PinboardKeys.addMenu,
        [
          PinboardKeys.tool(PinboardKinds.plain),
          PinboardKeys.tool(PinboardKinds.member),
          PinboardKeys.edgeTool,
        ],
      ),
      (PinboardKeys.drawMenu, [PinboardKeys.pen, PinboardKeys.strokeWidth]),
      (PinboardKeys.toolsMenu, [PinboardKeys.lasso, PinboardKeys.picture]),
    ]) {
      final button = tester.getCenter(find.byKey(menu));
      for (final option in options) {
        await reach(tester, menu, option);
        expect(find.byKey(option).hitTestable(), findsOneWidget);
      }
      // The choices stood where the buttons were; back brings them again.
      expect(find.byKey(menu).hitTestable(), findsNothing);
      await tester.tap(find.byKey(PinboardKeys.closeMenu));
      await settle(tester);
      expect(tester.getCenter(find.byKey(menu)), equals(button));
      expect(find.byKey(PinboardKeys.closeMenu), findsNothing);
    }
  });

  testWidgets('back from the pen puts it down', (tester) async {
    await seed(tester);
    await open(tester, size: const Size(390, 844));
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    await pick(tester, PinboardKeys.drawMenu, PinboardKeys.pen);
    await settle(tester);
    // Chosen, the menu stays.
    expect(find.byKey(PinboardKeys.pen).hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(PinboardKeys.closeMenu));
    await settle(tester);
    // A finger on the map moves it again: nothing is drawn.
    await tester.dragFrom(const Offset(120, 300), const Offset(80, 40));
    await settle(tester);
    final rows = await tester.runAsync(() => db.select(db.pinboardNodes).get());
    expect(rows!.where((row) => row.kind == PinboardKinds.drawing), isEmpty);
  });

  testWidgets('a connection is drawn element by element, on from the last', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    // No dot on an element any more: connecting is a tool of its own, its kinds a
    // level below it — here the arrow.
    expect(find.byKey(ValueKey('$meer-handle')), findsNothing);
    await pick(tester, PinboardKeys.addMenu, PinboardKeys.edgeTool);
    await settle(tester);
    await tester.tap(find.byKey(PinboardKeys.edgeStyleOf(1)));
    await settle(tester);

    Offset centreOf(String text) => tester.getCenter(
      find
          .ancestor(
            of: find.text(text),
            matching: find.byType(PinboardElementView),
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

    final edges = await tester.runAsync(
      () => db.select(db.pinboardEdges).get(),
    );
    expect({
      for (final edge in edges!) (edge.fromId, edge.toId),
    }, equals({(meer, berge), (berge, meer)}));
    expect(edges.map((edge) => edge.arrows), everyElement(PinboardArrows.end));

    // Back a level: the tool is put down, and a finger selects again.
    await tester.tap(find.byKey(PinboardKeys.closeMenu));
    await settle(tester);
    await tester.tap(find.text('Berge'));
    await settle(tester);
    expect(find.byKey(PinboardKeys.delete), findsOneWidget);
  });

  testWidgets('a stroke is taken on its line alone, not across its box', (
    tester,
  ) async {
    await seed(tester);
    // A line along the top of a box that holds "Berge" and the canvas below it.
    await tester.runAsync(
      () => container
          .read(pinboardRepositoryProvider)
          .addNode(
            pageId: pageId,
            kind: PinboardKinds.drawing,
            x: 280,
            y: -20,
            width: 200,
            height: 300,
            look: {WireFields.points: '0,0 10000,0', WireFields.strokeWidth: 4},
          ),
    );
    await open(tester);
    double zoom() =>
        tester.widget<PinboardScene>(find.byType(PinboardScene)).zoom;
    Rect rectOf(String text) => tester.getRect(
      find
          .ancestor(
            of: find.text(text),
            matching: find.byType(PinboardElementView),
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
    await tester.tap(find.byKey(PinboardKeys.fit));
    await settle(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    await pick(tester, PinboardKeys.addMenu, PinboardKeys.edgeTool);
    await settle(tester);
    await tester.tap(find.byKey(PinboardKeys.edgeStyleOf(1)));
    await settle(tester);
    await tester.dragFrom(
      rectOf('Meer').center,
      rectOf('Berge').center - rectOf('Meer').center,
    );
    await settle(tester);

    final edges = await tester.runAsync(
      () => db.select(db.pinboardEdges).get(),
    );
    expect([
      for (final edge in edges!) (edge.fromId, edge.toId),
    ], equals([(meer, berge)]));
  });

  testWidgets('a connection\'s colour and thickness are chosen before', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    await pick(tester, PinboardKeys.addMenu, PinboardKeys.edgeTool);
    await settle(tester);
    await tester.tap(find.byKey(PinboardKeys.edgeStyleOf(0)));
    await settle(tester);

    await reach(tester, PinboardKeys.addMenu, PinboardKeys.edgeColor);
    await tester.tap(find.byKey(PinboardKeys.edgeColor));
    await settle(tester);
    await tester.tap(find.byKey(PinboardKeys.swatch('RUST')));
    await tester.tap(find.byKey(PinboardKeys.save));
    await settle(tester);
    await reach(tester, PinboardKeys.addMenu, PinboardKeys.edgeWidth);
    await tester.tap(find.byKey(PinboardKeys.edgeWidth));
    await settle(tester);
    await tester.tap(find.byKey(PinboardKeys.choice('4')));
    await settle(tester);

    Offset centreOf(String text) => tester.getCenter(find.text(text));
    await tester.dragFrom(
      centreOf('Meer'),
      centreOf('Berge') - centreOf('Meer'),
    );
    await settle(tester);

    final edge = (await tester.runAsync(
      () => db.select(db.pinboardEdges).get(),
    ))!.single;
    expect(edge.color, equals('RUST'));
    expect(edge.strokeWidth, equals(4));
  });

  testWidgets('a drawn shape keeps its shape and is resized', (tester) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    await pick(tester, PinboardKeys.drawMenu, PinboardKeys.shapes);
    await settle(tester);
    await tester.tap(find.byKey(PinboardKeys.penShape('ellipse')));
    await settle(tester);
    await tester.dragFrom(const Offset(200, 400), const Offset(160, 100));
    await settle(tester);
    final drawn = (await tester.runAsync(
      () => db.select(db.pinboardNodes).get(),
    ))!.where((row) => row.kind == PinboardKinds.drawing).single;
    expect(drawn.shape, equals(PinboardShapes.ellipse));

    // Put down, it is selected — with a corner to resize it by.
    await tester.tap(find.byKey(PinboardKeys.closeMenu));
    await settle(tester);
    await tester.tapAt(const Offset(280, 400));
    await settle(tester);
    expect(find.byKey(ValueKey('${drawn.id}-resize')), findsOneWidget);
  });

  testWidgets('an element is turned by its knob, as one step', (tester) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    await tester.tap(find.text('Meer'));
    await settle(tester);

    final knob = find.byKey(ValueKey('$meer-rotate'));
    expect(knob, findsOneWidget);
    final centre = tester.getCenter(
      find
          .ancestor(
            of: find.text('Meer'),
            matching: find.byType(PinboardElementView),
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
        db.pinboardNodes,
      )..where((row) => row.id.equals(meer))).getSingle(),
    ))!.rotation;
    expect(await rotation(), equals(90));

    await tester.tap(find.byKey(PinboardKeys.undo));
    await settle(tester);
    expect(await rotation(), isNull);
  });

  testWidgets(
    'connecting by the list offers only elements a name tells apart',
    (tester) async {
      await seed(tester);
      final ids = (await tester.runAsync(() async {
        final maps = container.read(pinboardRepositoryProvider);
        Future<String> add(String kind, String text, {int x = 600}) =>
            maps.addNode(
              pageId: pageId,
              kind: kind,
              x: x,
              y: 200,
              width: 120,
              height: 80,
              text: text,
            );
        return (
          stroke: await add(PinboardKinds.drawing, ''),
          unnamed: await add(
            PinboardKinds.image,
            '![](hiwiski-image:a)',
            x: 800,
          ),
          named: await add(
            PinboardKinds.image,
            '![Strand](hiwiski-image:b)',
            x: 1000,
          ),
          empty: await add(PinboardKinds.note, '  ', x: 1200),
        );
      }))!;
      await open(tester);
      await tester.tap(find.byKey(PinboardKeys.edit));
      await settle(tester);
      await tester.tap(find.text('Meer'));
      await settle(tester);
      for (
        int turn = 0;
        find.byKey(PinboardKeys.connect).hitTestable().evaluate().isEmpty;
        turn++
      ) {
        if (turn > 5) fail('no way to connect in the corner');
        await turnCorner(tester);
      }
      await tester.tap(find.byKey(PinboardKeys.connect));
      await settle(tester);

      expect(find.byKey(PinboardKeys.connectTo(berge)), findsOneWidget);
      expect(find.byKey(PinboardKeys.connectTo(ids.named)), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(PinboardKeys.connectTo(ids.named)),
          matching: find.text('Strand'),
        ),
        findsOneWidget,
      );
      for (final hidden in [ids.stroke, ids.unnamed, ids.empty]) {
        expect(find.byKey(PinboardKeys.connectTo(hidden)), findsNothing);
      }
      expect(find.text('–'), findsNothing);
      // The two pictures are nowhere to be fetched: their retries end with the view.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 10));
    },
  );

  testWidgets('pictures chosen together stand side by side, as high as each '
      'other, and go with one Undo; a picture is replaced by one', (
    tester,
  ) async {
    final picker = (await tester.runAsync(
      () async => _Picker([
        _Picked('weit.png', await _png(200, 100)),
        _Picked('quadrat.png', await _png(100, 100)),
        _Picked('hoch.png', await _png(100, 200)),
      ]),
    ))!;
    final before = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = before);
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);

    Future<List<PinboardNodeRow>> pictures() async => [
      for (final row in (await tester.runAsync(
        () => db.select(db.pinboardNodes).get(),
      ))!)
        if (row.kind == PinboardKinds.image && row.deletedAt == null) row,
    ]..sort((a, b) => a.x.compareTo(b.x));

    await pick(
      tester,
      PinboardKeys.addMenu,
      PinboardKeys.tool(PinboardKinds.image),
    );
    // The pictures are read in for real: their shapes are decoded.
    for (int turn = 0; (await pictures()).length < 3; turn++) {
      if (turn > 20) fail('the pictures were not placed');
      await settle(tester);
    }
    expect(picker.asked, equals(['several']));
    final placed = await pictures();
    // In the order they were chosen, left to right, a gap apart, all as high and
    // each in its own shape — each its own picture.
    expect(placed.map((row) => row.body).toSet(), hasLength(3));
    final height = placed.first.height;
    for (final (index, aspect) in const [2.0, 1.0, 0.5].indexed) {
      final row = placed[index];
      expect(row.height, equals(height), reason: '$index');
      expect(row.width, closeTo(height * aspect, 1), reason: '$index');
      expect(row.y, equals(placed.first.y), reason: '$index');
      if (index > 0) {
        final left = placed[index - 1];
        expect(
          row.x - (left.x + left.width),
          closeTo(HiwiskiMetrics.pinboardRowGap, 1),
          reason: '$index',
        );
      }
    }

    // One Undo takes them all, one Redo brings them all back.
    await tester.tap(find.byKey(PinboardKeys.undo));
    await settle(tester);
    expect(await pictures(), isEmpty);
    await tester.tap(find.byKey(PinboardKeys.redo));
    await settle(tester);
    expect(await pictures(), hasLength(3));

    // Another picture for one of them: chosen alone.
    await tester.tap(find.byKey(ValueKey(placed.first.id)));
    await settle(tester);
    for (
      int turn = 0;
      find.byKey(PinboardKeys.editContent).hitTestable().evaluate().isEmpty;
      turn++
    ) {
      if (turn > 5) fail('no way to change the picture in the corner');
      await turnCorner(tester);
    }
    await tester.tap(find.byKey(PinboardKeys.editContent));
    for (int turn = 0; picker.asked.length < 2; turn++) {
      if (turn > 20) fail('no picture was asked for');
      await settle(tester);
    }
    await settle(tester);
    expect(picker.asked, equals(['several', 'one']));
    expect(await pictures(), hasLength(3));
  });

  testWidgets('a week of calendars shows the events of the calendars chosen, '
      'the current week moving on with the days, an event opening on hover', (
    tester,
  ) async {
    final wednesday = DateTime(2026, 11, 25, 9);
    await withClock(Clock.fixed(wednesday), () async {
      await seed(tester);
      final ids = (await tester.runAsync(() async {
        final calendars = container.read(calendarRepositoryProvider);
        final family = await calendars.createCalendar(
          name: 'Familie',
          colorToken: ColorTokens.blue,
        );
        final work = await calendars.createCalendar(
          name: 'Arbeit',
          colorToken: ColorTokens.rust,
        );
        Future<void> event(
          String calendarId,
          String title,
          DateTime start, {
          String? location,
        }) => calendars.createEvent(
          calendarId: calendarId,
          draft: EventDraft(
            title: title,
            time: TimedEvent(start, start.add(const Duration(hours: 1))),
            location: location,
          ),
        );
        await event(
          family,
          'Chorprobe',
          DateTime(2026, 11, 25, 19, 30),
          location: 'Gemeindehaus',
        );
        await event(work, 'Teamtreffen', DateTime(2026, 11, 26, 10));
        await event(family, 'Sommerfest', DateTime(2027, 7, 14, 15));
        return (family: family, work: work);
      }))!;
      await open(tester);
      await tester.tap(find.byKey(PinboardKeys.edit));
      await settle(tester);

      // Placed with the family's calendar and the current week.
      await pick(
        tester,
        PinboardKeys.addMenu,
        PinboardKeys.tool(PinboardKinds.calendar),
      );
      await settle(tester);
      expect(
        tester
            .widget<FilledButton>(find.byKey(PinboardKeys.calendarDone))
            .onPressed,
        isNull,
        reason: 'a week of no calendar is not placed',
      );
      await tester.tap(find.byKey(PinboardKeys.calendar(ids.family)));
      await tester.pump();
      await tester.tap(find.byKey(PinboardKeys.calendarDone));
      await settle(tester);
      Future<PinboardNodeRow> week() async => (await tester.runAsync(
        () => (db.select(
          db.pinboardNodes,
        )..where((row) => row.kind.equals(PinboardKinds.calendar))).getSingle(),
      ))!;
      final placed = await week();
      expect(placed.calendars, equals(ids.family));
      expect(placed.week, isNull);
      expect(find.textContaining('Week 48'), findsOneWidget);
      expect(find.textContaining('Chorprobe'), findsOneWidget);
      // Another calendar's events are not this week's of these calendars.
      expect(find.textContaining('Teamtreffen'), findsNothing);
      expect(find.textContaining('Sommerfest'), findsNothing);

      // Where the map is read, an event opens into its card on hover.
      await tester.tap(find.byKey(PinboardKeys.edit));
      await settle(tester);
      final mouse = await tester.createGesture(kind: .mouse);
      await mouse.addPointer(location: .zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.textContaining('Chorprobe')));
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      expect(find.textContaining('Gemeindehaus'), findsOneWidget);
      await mouse.moveTo(Offset.zero);
      await settle(tester);

      // A week of the year stays where it is.
      final node = (await tester.runAsync(
        () => container.read(pinboardRepositoryProvider).node(placed.id),
      ))!;
      await tester.runAsync(
        () => container.read(pinboardRepositoryProvider).changeNode(node, {
          WireFields.week: '2027-W28',
        }),
      );
      await settle(tester);
      expect(find.textContaining('Week 28'), findsOneWidget);
      expect(find.textContaining('Sommerfest'), findsOneWidget);
      expect(find.textContaining('Chorprobe'), findsNothing);
    });

    // The current week is the week it is: the map opened again in July 2027 shows
    // that week's.
    await tester.runAsync(() async {
      final maps = container.read(pinboardRepositoryProvider);
      final row = await (db.select(
        db.pinboardNodes,
      )..where((row) => row.kind.equals(PinboardKinds.calendar))).getSingle();
      final node = await maps.node(row.id);
      if (node != null) await maps.changeNode(node, {WireFields.week: null});
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await withClock(Clock.fixed(DateTime(2027, 7, 13, 9)), () async {
      await open(tester);
      expect(find.textContaining('Week 28'), findsOneWidget);
      expect(find.textContaining('Sommerfest'), findsOneWidget);
    });
  });

  testWidgets('a note\'s heading stays larger than its text at any text '
      'size', (tester) async {
    await seed(tester);
    await tester.runAsync(
      () => container
          .read(pinboardRepositoryProvider)
          .addNode(
            pageId: pageId,
            kind: PinboardKinds.note,
            x: 0,
            y: 200,
            width: 480,
            height: 200,
            text: '# Packliste\n\nZelt',
            look: const {WireFields.textSize: PinboardTextSizes.xLarge},
          ),
    );
    await open(tester);
    final [heading, text] = noteLines(tester);
    expect(heading.text, equals('Packliste'));
    expect(text.text, equals('Zelt'));
    // At the theme's own size, a heading came out smaller than the text below it
    // once the note's text was made large.
    expect(heading.rect.height, greaterThan(text.rect.height));
  });

  testWidgets('a note\'s text is placed in its middle, its list too, and back '
      'with Undo', (tester) async {
    await seed(tester);
    final note = (await tester.runAsync(
      () => container
          .read(pinboardRepositoryProvider)
          .addNode(
            pageId: pageId,
            kind: PinboardKinds.note,
            x: 0,
            y: 200,
            width: 240,
            height: 160,
            text: 'Packliste\n\n- Zelt\n- Kocher',
          ),
    ))!;
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    final room = tester.getRect(find.byType(PinboardNote));
    // At the top left at first: each line at the note's start, the list's marker
    // leading its line.
    final before = noteLines(tester);
    expect(
      before.map((line) => line.text),
      equals(['Packliste', '•\u00A0Zelt', '•\u00A0Kocher']),
    );
    for (final line in before) {
      expect(line.rect.left, closeTo(room.left, 1), reason: line.text);
    }
    expect(before.first.rect.top, closeTo(room.top, 1));
    await tester.tap(
      find
          .ancestor(
            of: find.byType(PinboardNote),
            matching: find.byType(PinboardElementView),
          )
          .first,
    );
    await settle(tester);
    for (
      int turn = 0;
      find.byKey(PinboardKeys.textAlign).hitTestable().evaluate().isEmpty;
      turn++
    ) {
      if (turn > 5) fail('no text placement in the corner');
      await turnCorner(tester);
    }
    await tester.tap(find.byKey(PinboardKeys.textAlign));
    await settle(tester);
    await tester.tap(
      find.byKey(PinboardKeys.textAlignOf(PinboardTextAligns.center)),
    );
    await settle(tester);

    Future<PinboardNodeRow> stored() async => (await tester.runAsync(
      () => (db.select(
        db.pinboardNodes,
      )..where((row) => row.id.equals(note))).getSingle(),
    ))!;
    expect((await stored()).textAlign, equals(PinboardTextAligns.center));
    // Drawn in the note's middle, across and up and down — each short line, the
    // list's too.
    final middle = tester.getRect(find.byType(PinboardNote)).center;
    final placed = noteLines(tester);
    for (final line in placed) {
      expect(line.rect.width, lessThan(room.width * 0.75), reason: line.text);
      expect(line.rect.center.dx, closeTo(middle.dx, 1), reason: line.text);
    }
    final text = placed
        .map((line) => line.rect)
        .reduce((all, line) => all.expandToInclude(line));
    expect(text.center.dy, closeTo(middle.dy, 1));

    // Switched to follow the shape and back in the same sheet: both are
    // written, the second on what the first left.
    await tester.tap(find.byKey(PinboardKeys.textAlign));
    await settle(tester);
    await tester.tap(find.byKey(PinboardKeys.textFlow));
    await settle(tester);
    expect((await stored()).textFlow, equals(PinboardTextFlows.shape));
    await tester.tap(find.byKey(PinboardKeys.textFlow));
    await settle(tester);
    expect((await stored()).textFlow, isNull);
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);

    for (int step = 0; step < 3; step++) {
      await tester.tap(find.byKey(PinboardKeys.undo));
      await settle(tester);
    }
    expect((await stored()).textAlign, isNull);
    expect((await stored()).textFlow, isNull);
  });

  // As on a page, and as a link chip is followed: a packing list is worked through
  // where it is read. While editing, a tap on a note selects it.
  testWidgets(
    'a note\'s box is ticked with a tap where the map is read, not while editing',
    (tester) async {
      await seed(tester);
      final note = (await tester.runAsync(
        () => container
            .read(pinboardRepositoryProvider)
            .addNode(
              pageId: pageId,
              kind: PinboardKinds.note,
              x: 0,
              y: 200,
              width: 240,
              height: 160,
              text: 'Packliste\n\n- [ ] Zelt\n- [ ] Kocher',
            ),
      ))!;
      await open(tester);
      Future<String> stored() async => (await tester.runAsync(
        () => (db.select(
          db.pinboardNodes,
        )..where((row) => row.id.equals(note))).getSingle(),
      ))!.body;
      Finder unticked() => find.descendant(
        of: find.byType(PinboardNote),
        matching: find.byIcon(HiwiskiSymbols.checkBoxOutlineBlank),
      );
      expect(unticked(), findsNWidgets(2));

      await tester.tap(unticked().last);
      await settle(tester);
      expect(await stored(), equals('Packliste\n\n- [ ] Zelt\n- [x] Kocher'));
      expect(unticked(), findsOneWidget);

      await tester.tap(find.byKey(PinboardKeys.edit));
      await settle(tester);
      await tester.tap(unticked(), warnIfMissed: false);
      await settle(tester);
      expect(await stored(), equals('Packliste\n\n- [ ] Zelt\n- [x] Kocher'));
    },
  );

  // Text, boxes and pictures grow together with the element's text size: its text
  // scaled alone outgrew a list's boxes and squeezed a recipe's picture beside it.
  testWidgets('a link\'s content grows as a whole with its text size', (
    tester,
  ) async {
    await seed(tester);
    final link = (await tester.runAsync(() async {
      final wiki = container.read(wikiRepositoryProvider);
      final packing = await wiki.createPage(title: 'Packen');
      await wiki.updatePage(
        (await wiki.watchPage(packing).first)!,
        content: '- [ ] Zelt',
      );
      return container
          .read(pinboardRepositoryProvider)
          .addNode(
            pageId: pageId,
            kind: PinboardKinds.link,
            x: 0,
            y: 200,
            width: 360,
            height: 300,
            look: {
              WireFields.target: 'hiwiski://wiki_page/$packing',
              WireFields.linkView: PinboardLinkViews.content,
            },
          );
    }))!;
    await open(tester);
    Finder inContent(Finder finder) =>
        find.descendant(of: find.byType(PinboardLinkContent), matching: finder);
    double boxToWords() {
      final box = tester.getRect(
        inContent(
          find.byWidgetPredicate(
            (widget) =>
                widget is Icon &&
                (widget.icon == HiwiskiSymbols.checkBoxOutlineBlank ||
                    widget.icon == Icons.check_box_outline_blank),
          ),
        ).first,
      );
      final words = tester.getRect(
        inContent(find.textContaining('Zelt', findRichText: true)).first,
      );
      return box.height / words.height;
    }

    final medium = boxToWords();
    await tester.runAsync(() async {
      final maps = container.read(pinboardRepositoryProvider);
      await maps.changeNode((await maps.node(link))!, {
        WireFields.textSize: PinboardTextSizes.xLarge,
      });
    });
    await settle(tester);
    expect(boxToWords(), closeTo(medium, 0.01));
  });

  // A kind described for the rules and drawn, but forgotten on the "Add" menu,
  // could only come from another device.
  testWidgets('every kind but a stroke is on the "Add" menu', (tester) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    for (final kind in pinboardKinds) {
      if (kind == PinboardKinds.drawing) continue;
      await reach(tester, PinboardKeys.addMenu, PinboardKeys.tool(kind));
      expect(find.byKey(PinboardKeys.tool(kind)), findsOneWidget, reason: kind);
    }
  });

  testWidgets('a new link shows what it points to', (tester) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    await pick(
      tester,
      PinboardKeys.addMenu,
      PinboardKeys.tool(PinboardKinds.link),
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

    final rows = await tester.runAsync(() => db.select(db.pinboardNodes).get());
    final link = rows!.singleWhere((row) => row.kind == PinboardKinds.link);
    expect(link.linkView, equals(PinboardLinkViews.content));
    expect(
      link.height,
      equals(HiwiskiMetrics.pinboardLinkContentSize.height.round()),
    );
  });

  testWidgets('a shape is drawn in the pen\'s colour as a stroke', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    await pick(tester, PinboardKeys.drawMenu, PinboardKeys.shapes);
    await settle(tester);
    await tester.tap(find.byKey(PinboardKeys.penShape('rectangle')));
    await settle(tester);

    await tester.dragFrom(const Offset(200, 400), const Offset(160, 100));
    await settle(tester);

    final rows = await tester.runAsync(() => db.select(db.pinboardNodes).get());
    final drawn = rows!
        .where((row) => row.kind == PinboardKinds.drawing)
        .single;
    // Its four corners, each given twice so it stays sharp, and closed.
    expect(drawn.points!.split(' '), hasLength(10));
    // As wide as the drag went, and the pen's width on both sides.
    expect(drawn.width, closeTo(160 + HiwiskiMetrics.pinboardPenWidths[1], 2));
  });

  testWidgets('a finger tapped twice and dragged down zooms in', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    double zoom() =>
        tester.widget<PinboardScene>(find.byType(PinboardScene)).zoom;
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
          .read(pinboardRepositoryProvider)
          .addNode(
            pageId: pageId,
            kind: PinboardKinds.plain,
            x: 2400,
            y: 0,
            width: 160,
            height: 40,
            text: 'Wüste',
          ),
    );
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    final meerBox = tester.getRect(
      find
          .ancestor(
            of: find.text('Meer'),
            matching: find.byType(PinboardElementView),
          )
          .first,
    );
    final zoom = tester.widget<PinboardScene>(find.byType(PinboardScene)).zoom;
    // Far smaller on screen than a finger.
    final height = 40 * zoom;
    expect(height, lessThan(HiwiskiMetrics.minTapTarget / 2));
    // Just above it: outside the snippet, within a finger's width of it.
    await tester.tapAt(meerBox.center - Offset(0, height / 2 + 6));
    await settle(tester);
    expect(find.byKey(PinboardKeys.delete), findsOneWidget);
  });

  testWidgets('a search marks what it found and lists it', (tester) async {
    await seed(tester);
    await open(tester);

    await tester.tap(find.byKey(PinboardKeys.search));
    await settle(tester);
    await tester.enterText(find.byKey(PinboardKeys.searchField), 'mee');
    await settle(tester);

    expect(find.byKey(PinboardKeys.hit(meer)), findsOneWidget);
    expect(find.text('1 match'), findsOneWidget);
  });

  testWidgets('Enter in the search goes from hit to hit, again and again', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.search));
    await settle(tester);
    // "Meer" and "Berge", in that order.
    await tester.enterText(find.byKey(PinboardKeys.searchField), 'e');
    await settle(tester);
    String shown() {
      final results = tester.widget<PinboardResults>(
        find.byType(PinboardResults),
      );
      return results.hits[results.current].id;
    }

    expect(shown(), equals(meer));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    expect(shown(), equals(berge));
    expect(
      tester
          .widget<TextField>(find.byKey(PinboardKeys.searchField))
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
    await tester.tap(find.byKey(PinboardKeys.search));
    await settle(tester);
    await tester.enterText(find.byKey(PinboardKeys.searchField), 'e');
    await settle(tester);
    String shown() {
      final results = tester.widget<PinboardResults>(
        find.byType(PinboardResults),
      );
      return results.hits[results.current].id;
    }

    await tester.tap(find.byKey(PinboardKeys.searchNext));
    await settle(tester);
    expect(shown(), equals(berge));
    final maps = container.read(pinboardRepositoryProvider);

    // A hit added before it in the list: still "Berge", not the one now in its
    // place.
    await tester.runAsync(
      () => maps.addNode(
        pageId: pageId,
        kind: PinboardKinds.plain,
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
      await maps.changeNode((await maps.node(meer))!, {WireFields.x: 20});
    });
    await settle(tester);
    expect(shown(), equals(berge));

    // A new search begins at its first hit.
    await tester.enterText(find.byKey(PinboardKeys.searchField), 'er');
    await settle(tester);
    expect(shown(), equals(meer));
  });

  testWidgets('while searching, the hit shown is marked, not selected', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    await tester.tap(find.byKey(PinboardKeys.search));
    await settle(tester);
    await tester.enterText(find.byKey(PinboardKeys.searchField), 'Meer');
    await settle(tester);

    final element = find.byWidgetPredicate(
      (widget) => widget is PinboardElementView && widget.node.id == meer,
    );
    // Framed as it is shown, but without grips to resize or turn it.
    expect(tester.widget<PinboardElementView>(element).selected, isTrue);
    expect(find.byKey(ValueKey('$meer-resize')), findsNothing);
    expect(find.byKey(ValueKey('$meer-rotate')), findsNothing);

    // A tap selects it, as any element; it does not open its text.
    await tester.tapAt(tester.getCenter(element));
    await settle(tester);
    expect(find.byKey(PinboardKeys.textField), findsNothing);
    expect(find.byKey(ValueKey('$meer-resize')), findsOneWidget);
  });

  testWidgets('on a phone the search takes the whole line and is ended', (
    tester,
  ) async {
    await seed(tester);
    await open(tester, size: const Size(390, 844));
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);

    await tester.tap(find.byKey(PinboardKeys.search));
    await settle(tester);
    // The editing buttons make room.
    expect(find.byKey(PinboardKeys.undo), findsNothing);
    await tester.enterText(find.byKey(PinboardKeys.searchField), 'Berge');
    await settle(tester);

    // What is typed shows, whole; the field takes most of the line.
    final field = tester.getRect(find.byKey(PinboardKeys.searchField));
    expect(field.width, greaterThan(200));
    final typed = tester.getRect(
      find.descendant(
        of: find.byKey(PinboardKeys.searchField),
        matching: find.byType(EditableText),
      ),
    );
    expect(typed.right, lessThanOrEqualTo(390));
    // The count and the way from hit to hit on a line of their own.
    expect(find.byKey(PinboardKeys.searchCount).hitTestable(), findsOneWidget);
    expect(
      tester.getRect(find.byKey(PinboardKeys.searchCount)).top,
      greaterThan(field.bottom),
    );
    expect(find.byKey(PinboardKeys.searchNext).hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(PinboardKeys.search));
    await settle(tester);
    expect(find.byKey(PinboardKeys.searchField), findsNothing);
    expect(find.byKey(PinboardKeys.searchCount), findsNothing);
    expect(find.byKey(PinboardKeys.undo).hitTestable(), findsOneWidget);
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
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    await pick(tester, PinboardKeys.drawMenu, PinboardKeys.pen);
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

    await tester.tap(find.byKey(PinboardKeys.fit));
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
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    final element = find
        .ancestor(
          of: find.text('Berge'),
          matching: find.byType(PinboardElementView),
        )
        .first;
    await tester.dragFrom(
      tester.getRect(element).center,
      const Offset(100, 50),
    );
    await settle(tester);
    Future<int> bergeX() async => (await tester.runAsync(
      () => container.read(pinboardRepositoryProvider).node(berge),
    ))!.x;
    final moved = await bergeX();
    expect(moved, isNot(equals(300)));

    await tester.runAsync(() async {
      final wiki = container.read(wikiRepositoryProvider);
      await wiki.archivePage((await wiki.watchPage(pageId).first)!);
    });
    await settle(tester);
    expect(find.byKey(PinboardKeys.addMenu), findsNothing);

    // The move is not taken back …
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await settle(tester);
    expect(await bergeX(), equals(moved));
    // … and a tap reads the snippet instead of writing it.
    await tester.tap(find.text('Berge'));
    await settle(tester);
    expect(find.byKey(PinboardKeys.textField), findsNothing);
  });

  testWidgets('a moved element stays where it was let go', (tester) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    final element = find
        .ancestor(
          of: find.text('Berge'),
          matching: find.byType(PinboardElementView),
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
          .read(pinboardRepositoryProvider)
          .addNode(
            pageId: pageId,
            kind: PinboardKinds.note,
            x: 0,
            y: 200,
            width: 200,
            height: 100,
            text: 'Notiz',
          ),
    );
    await open(tester);
    await tester.tap(find.byKey(PinboardKeys.edit));
    await settle(tester);
    final element = find
        .ancestor(
          of: showing('Notiz'),
          matching: find.byType(PinboardElementView),
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
    const gap = HiwiskiMetrics.pinboardFrameGap;
    await tester.dragFrom(
      before.bottomRight + const Offset(gap, gap),
      const Offset(50, 20),
    );
    await settle(tester);

    final row = await tester.runAsync(
      () => (db.select(
        db.pinboardNodes,
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
          .read(pinboardRepositoryProvider)
          .addNode(
            pageId: pageId,
            kind: PinboardKinds.link,
            x: 0,
            y: 200,
            width: 360,
            height: 420,
            look: {
              WireFields.target: 'hiwiski://wiki_page/$pageId',
              WireFields.linkView: PinboardLinkViews.content,
            },
          ),
    );
    await open(tester);

    // On the canvas its content — the page, with the map's picture below it; in
    // that picture the same element by its title only.
    expect(find.byType(PinboardPreviewCard), findsOneWidget);
    expect(find.byType(PinboardLinkContent), findsOneWidget);
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
              entityType: EntityTypes.pinboardNode,
              entityId: meer,
              field: WireFields.text,
              mine: '"Meer und Strand"',
              theirs: '"Meer"',
              detectedAt: clock.now(),
            ),
          ),
    );
    await open(tester);

    await tester.tap(find.byKey(PinboardKeys.conflicts));
    await settle(tester);
    // On the map, beside the map's version — no sheet over it — and in the bar
    // below, next to "Meer".
    expect(find.text('Meer und Strand'), findsNWidgets(2));
    expect(find.text('Yours'), findsWidgets);
    await tester.tap(find.byKey(PinboardKeys.keepTheirs));
    await settle(tester);

    final left = await tester.runAsync(() => db.select(db.conflicts).get());
    expect(left, isEmpty);
    expect(find.byKey(PinboardKeys.conflicts), findsNothing);
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
              entityType: EntityTypes.pinboardNode,
              entityId: meer,
              field: WireFields.textSize,
              mine: '"24"',
              theirs: '"${PinboardTextSizes.large}"',
              detectedAt: clock.now(),
            ),
          ),
    );
    await open(tester);

    await tester.tap(find.byKey(PinboardKeys.conflicts));
    await settle(tester);
    final bar = find.byType(PinboardConflictBar);
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
                entityType: EntityTypes.pinboardNode,
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

    await tester.tap(find.byKey(PinboardKeys.conflicts));
    await settle(tester);
    expect(find.text('On the pinboard: Position'), findsOneWidget);
    // The map's version where it is, this device's where it was moved to.
    expect(find.text('Meer'), findsNWidgets(2));
    // Both of the position's fields go with the one decision.
    await tester.tap(find.byKey(PinboardKeys.keepTheirs));
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
                entityType: EntityTypes.pinboardNode,
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
    await tester.tap(find.text('Show on the pinboard'));
    await settle(tester);

    // Decided on this map, not on a second one opened over it.
    expect(find.byType(PinboardScreen), findsOneWidget);
    expect(find.text('On the pinboard: Position'), findsOneWidget);
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
                  entityType: EntityTypes.pinboardNode,
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
          .read(pinboardRepositoryProvider)
          .addNode(
            pageId: pageId,
            kind: PinboardKinds.member,
            x: 0,
            y: 200,
            width: 80,
            height: 80,
            look: {WireFields.target: memberAddressOf('anna')},
          );
      await db
          .into(db.conflicts)
          .insert(
            ConflictRow(
              id: '$member:${WireFields.target}',
              entityType: EntityTypes.pinboardNode,
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
      find.byKey(PinboardKeys.release).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(PinboardKeys.release));
    await settle(tester);
  }
  final corner = tester.widget<PinboardCorner>(find.byType(PinboardCorner));
  final open = switch (corner.open) {
    final index? => corner.menus[index].key,
    null => null,
  };
  if (open != menu) {
    // On a phone another menu's choices stand where its button was: back first.
    if (find.byKey(menu).hitTestable().evaluate().isEmpty &&
        find.byKey(PinboardKeys.closeMenu).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(PinboardKeys.closeMenu));
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
  final corner = find.byType(PinboardCorner);
  // The rings go round the screen's corner — the corner's box's own.
  final centre = tester.getRect(corner).bottomRight;
  final ring = pinboardCornerLayout(
    compact: tester.widget<PinboardCorner>(corner).compact,
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

PinboardNode _node(
  String id, {
  required int x,
  required int y,
  required int width,
  required int height,
  required String text,
  String kind = PinboardKinds.plain,
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

/// The system's file dialog, handing over [files]: all of them where several may be
/// chosen, the first where one is asked for. [asked] says which way it was asked.
final class _Picker extends FilePickerPlatform {
  _Picker(this.files);

  final List<PlatformFile> files;
  final asked = <String>[];

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = .any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    asked.add('several');
    return files;
  }

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = .any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    asked.add('one');
    return files.firstOrNull;
  }
}

/// A picture chosen in the dialog, held in memory.
final class _Picked extends PlatformFile {
  _Picked(this.name, this._bytes);

  @override
  final String name;

  final Uint8List _bytes;

  @override
  Uri get uri => .new(scheme: 'memory', path: name);

  // Its type is cross_file's, which the app does not name itself: the app reads a
  // chosen file through readAsBytes, never through this.
  @override
  // ignore: always_declare_return_types
  get xFile => throw UnimplementedError('read through readAsBytes');

  @override
  int? lengthSync() => _bytes.length;

  @override
  Future<int?> length() async => _bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Stream<Uint8List> readAsByteStream() => .value(_bytes);
}

/// A picture [width] × [height] large, as a PNG — from inside `runAsync`.
Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF2E7D6B),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
