import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/todo/kanban.dart';
import 'package:hiwiski/features/todo/kanban/view/kanban_board.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/features/todo/kanban/kanban_view_model.dart';

/// **Wide, the columns side by side; on the phone one at a time, its neighbours
/// showing at the edges** — and a card dragged to another column lands there.
void main() {
  late HiwiskiDatabase db;
  late LocalSettings settings;
  late String listId;

  const todo = KanbanColumn(id: 'c-todo', name: 'To do');
  const doing = KanbanColumn(id: 'c-doing', name: 'Doing');
  const done = KanbanColumn(id: 'c-done', name: 'Done', done: true);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await LocalSettings.open();
    db = HiwiskiDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
      ],
    );
    final repository = container.read(todoRepositoryProvider);
    listId = await repository.createList(
      name: 'Move',
      kind: kindKanban,
      columns: const [todo, doing, done],
      tags: const ['tag-move'],
    );
    await repository.createTodo(listId: listId, title: 'Pack boxes');
    await repository.createTodo(
      listId: listId,
      title: 'Book the van',
      columnId: doing.id,
    );
    container.dispose();
  });

  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpBoard(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          localSettingsProvider.overrideWithValue(settings),
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
            body: Consumer(
              builder: (context, ref, _) {
                final state = ref.watch(kanbanViewModelProvider(listId)).value;
                if (state == null) return const SizedBox();
                return KanbanBoard(
                  list: state.list,
                  columns: state.columns,
                  cards: state.items,
                  writable: true,
                  mayMove: (_) => true,
                );
              },
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  testWidgets('wide, every column stands side by side', (tester) async {
    await pumpBoard(tester, const Size(1200, 800));

    expect(find.byKey(const ValueKey('kanban-pages')), findsNothing);
    for (final column in const [todo, doing, done]) {
      expect(
        find.byKey(ValueKey('kanban-column-${column.id}')),
        findsOneWidget,
      );
    }
    expect(find.text('Pack boxes'), findsOneWidget);
    expect(find.text('Book the van'), findsOneWidget);
    // The done column takes no new cards — new ones are work to do.
    expect(find.byKey(ValueKey('kanban-add-${done.id}')), findsNothing);
    await unmount(tester);
  });

  testWidgets('on the phone one column at a time, with tabs above', (
    tester,
  ) async {
    await pumpBoard(tester, const Size(390, 800));

    expect(find.byKey(const ValueKey('kanban-pages')), findsOneWidget);
    expect(find.byKey(ValueKey('kanban-tab-${done.id}')), findsOneWidget);
    // The first column fills most of the width, the next one peeks in at the edge.
    final first = tester.getRect(
      find.byKey(ValueKey('kanban-column-${todo.id}')),
    );
    expect(first.width, greaterThan(390 * 0.75));
    final next = find.byKey(ValueKey('kanban-column-${doing.id}'));
    expect(next, findsOneWidget);
    expect(tester.getRect(next).left, lessThan(390));

    // A tap on a tab jumps there.
    await tester.tap(find.byKey(ValueKey('kanban-tab-${done.id}')));
    await settle(tester);
    expect(
      tester.getRect(find.byKey(ValueKey('kanban-column-${done.id}'))).left,
      lessThan(390 * 0.2),
    );
    await unmount(tester);
  });

  testWidgets('a card dragged into the done column is done', (tester) async {
    await pumpBoard(tester, const Size(1200, 800));

    final card = find.byKey(
      ValueKey(
        'kanban-card-${(await db.select(db.todos).get()).firstWhere((t) => t.title == 'Pack boxes').id}',
      ),
    );
    final target = tester.getCenter(
      find.byKey(ValueKey('kanban-column-${done.id}')),
    );

    // Touch is the default platform in tests: a long press picks the card up.
    final gesture = await tester.startGesture(tester.getCenter(card));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await settle(tester);

    final moved = (await db.select(db.todos).get()).firstWhere(
      (t) => t.title == 'Pack boxes',
    );
    expect(moved.status, equals('DONE'));
    expect(moved.columnId, equals(done.id));
    await unmount(tester);
  });

  // A card could not be taken further down than the column showed: the column did
  // not scroll while one was held at its bottom.
  testWidgets('a card held at the bottom of a column scrolls it', (
    tester,
  ) async {
    // Real database work: outside the test's fake clock.
    await tester.runAsync(() async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          localSettingsProvider.overrideWithValue(settings),
        ],
      );
      for (int i = 0; i < 20; i++) {
        await container
            .read(todoRepositoryProvider)
            .createTodo(listId: listId, title: 'Box $i');
      }
      container.dispose();
    });
    await pumpBoard(tester, const Size(1200, 500));

    final column = find.byKey(ValueKey('kanban-column-${todo.id}'));
    final scrollable = find.descendant(
      of: column,
      matching: find.byType(Scrollable),
    );
    double offset() =>
        tester.state<ScrollableState>(scrollable.first).position.pixels;
    expect(offset(), equals(0));

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Pack boxes')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    final bottom = tester.getRect(column).bottom;
    await gesture.moveTo(Offset(tester.getCenter(column).dx, bottom - 70));
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(offset(), greaterThan(0));
    await gesture.up();
    await settle(tester);
    await unmount(tester);
  });

  testWidgets('a tap on the delete symbol only says to hold it', (
    tester,
  ) async {
    await pumpBoard(tester, const Size(1200, 800));
    final id = (await tester.runAsync(() => db.select(db.todos).get()))!
        .firstWhere((t) => t.title == 'Pack boxes')
        .id;

    await tester.tap(find.byKey(ValueKey('delete-todo-$id')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Hold to delete'), findsOneWidget);
    expect(find.text('Pack boxes'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await unmount(tester);
  });

  // Held, the symbol deletes the card — not the long press that picks it up — and
  // the note offers to take it back.
  testWidgets('held, the delete symbol deletes the card, and undo brings it '
      'back', (tester) async {
    await pumpBoard(tester, const Size(1200, 800));
    final id = (await tester.runAsync(() => db.select(db.todos).get()))!
        .firstWhere((t) => t.title == 'Pack boxes')
        .id;

    final press = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey('delete-todo-$id'))),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await press.up();
    await settle(tester);

    expect(find.text('Pack boxes'), findsNothing);
    expect(find.text('“Pack boxes” deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(find.text('Pack boxes'), findsOneWidget);
    // Nothing went out: the task is still there, not deleted.
    final row = (await tester.runAsync(() => db.select(db.todos).get()))!
        .firstWhere((t) => t.id == id);
    expect(row.deletedAt, isNull);
    await tester.pump(const Duration(seconds: 5));
    await unmount(tester);
  });

  testWidgets('held and let go without moving, the title is edited on the '
      'card', (tester) async {
    await pumpBoard(tester, const Size(1200, 800));
    final before = (await tester.runAsync(() => db.select(db.todos).get()))!
        .firstWhere((t) => t.title == 'Pack boxes');

    final press = await tester.startGesture(
      tester.getCenter(find.text('Pack boxes')),
    );
    await tester.pump(const Duration(seconds: 1));
    await press.up();
    await settle(tester);

    final field = find.byKey(ValueKey('title-field-${before.id}'));
    expect(field, findsOneWidget);
    // No dialog, no sheet: the field sits on the card.
    expect(
      find.descendant(
        of: find.byKey(ValueKey('kanban-card-${before.id}')),
        matching: field,
      ),
      findsOneWidget,
    );
    await tester.enterText(field, 'Pack the boxes');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    // The title's write and the stream after it run on the real clock.
    for (int i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Pack the boxes'), findsOneWidget);
    final after = (await tester.runAsync(() => db.select(db.todos).get()))!
        .firstWhere((t) => t.id == before.id);
    expect(after.title, equals('Pack the boxes'));
    // Let go where it was, it stayed where it was.
    expect(after.position, equals(before.position));
    expect(after.columnId, equals(before.columnId));
    await unmount(tester);
  });

  testWidgets('a new card goes to the bottom of its column', (tester) async {
    await pumpBoard(tester, const Size(1200, 800));

    await tester.tap(find.byKey(ValueKey('kanban-add-${doing.id}')));
    await tester.pump();
    await tester.enterText(
      find.byKey(ValueKey('kanban-new-${doing.id}')),
      'Cancel internet',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await settle(tester);

    final added = (await db.select(db.todos).get()).firstWhere(
      (t) => t.title == 'Cancel internet',
    );
    expect(added.columnId, equals(doing.id));
    expect(added.position, equals(positionStep));
    // A new card starts with the list's tags.
    expect(added.tags, equals('tag-move'));
    expect(find.text('Cancel internet'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a card has no check box — it is done by its column', (
    tester,
  ) async {
    await pumpBoard(tester, const Size(1200, 800));

    expect(find.text('Pack boxes'), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);
    await unmount(tester);
  });

  // A long column scrolled down: the cards above the viewport are not built. Skipped,
  // they made a drop after the 20th card land around the 10th.
  test('cards above the viewport count as passed', () {
    final middles = <double?>[
      ...List<double?>.filled(10, null),
      100,
      200,
      300,
      null,
      null,
    ];

    expect(slotIndex(middles, 250), equals(12));
    expect(slotIndex(middles, 50), equals(10));
    expect(slotIndex(<double?>[100, 200, null], 250), equals(2));
  });
}
