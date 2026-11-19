import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/ui/ui_keys.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/components/rich_text/view/markdown_toolbar.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/core/ui/undo_snack_bar.dart';
import 'package:hiwiski/features/todo/checklist/view/checklist_screen.dart';
import 'package:hiwiski/features/todo/view/todo_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **"Edit" opens name and description on the page itself**, and below them what is
/// done to the whole list: untick all, delete the ticked-off ones.
void main() {
  late HiwiskiDatabase db;
  late LocalSettings settings;
  late String listId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await LocalSettings.open();
    db = HiwiskiDatabase(NativeDatabase.memory());
  });

  /// Three chores, two of them ticked off. Real async: the database's streams do not
  /// run under the widget test's fake clock.
  Future<void> seed(WidgetTester tester) => tester.runAsync(() async {
    final container = ProviderContainer(
      retry: noRetry,
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
      ],
    );
    final todos = container.read(todoRepositoryProvider);
    listId = await todos.createList(name: 'Chores', kind: ListKinds.standard);
    for (final title in ['Dishes', 'Laundry', 'Windows']) {
      await todos.createTodo(listId: listId, title: title);
    }
    for (final todo in (await todos.watchTodos(listId).first).take(2)) {
      await todos.setStatus(todo, true);
    }
    container.dispose();
  });

  tearDown(() => db.close());

  /// Lets the database's writes and streams through, which run on the real clock.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester) async {
    await seed(tester);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
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
          home: ChecklistScreen(listId: listId),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Edit'));
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pump(UndoWindow.fallback + const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    // The streams close on a timer of their own.
    await settle(tester);
  }

  testWidgets('name and description are fields on the page, not a sheet', (
    tester,
  ) async {
    await open(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Edit'), findsNothing);

    // The description is written like a wiki page: with the insert bar.
    expect(find.byType(MarkdownToolbar), findsOneWidget);
    await tester.enterText(find.byKey(TodoKeys.listName), 'Housework');
    await tester.enterText(
      find.byKey(TodoKeys.listDescription),
      '## Weekly\n\n- [ ] Vacuum',
    );
    await tester.tap(find.byKey(CoreKeys.editSave));
    await settle(tester);

    expect(find.byKey(TodoKeys.listName), findsNothing);
    expect(find.text('Housework'), findsWidgets);
    // Read as Markdown: the heading without its hashes, the box as a box.
    expect(find.text('Weekly'), findsOneWidget);
    expect(find.textContaining('##'), findsNothing);
    expect(find.text('Vacuum'), findsOneWidget);
    await close(tester);
  });

  testWidgets('untick all leaves no entry ticked off', (tester) async {
    await open(tester);
    expect(find.text('Untick all (2)'), findsOneWidget);
    await tester.tap(find.byKey(TodoKeys.listUntickAll));
    await settle(tester);
    expect(find.text('Untick all'), findsOneWidget);
    expect(find.text('Delete ticked-off'), findsOneWidget);
    await close(tester);
  });

  testWidgets('delete ticked-off removes them, undo brings them back', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(TodoKeys.listDeleteDone));
    await settle(tester);
    expect(find.text('Dishes'), findsNothing);
    expect(find.text('Laundry'), findsNothing);
    expect(find.text('Windows'), findsOneWidget);
    expect(find.text('2 ticked-off entries deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(find.text('Dishes'), findsOneWidget);
    expect(find.text('Laundry'), findsOneWidget);
    await close(tester);
  });

  // Saved in between: "Undo" still brings them back.
  testWidgets('delete ticked-off, save, then undo brings them back', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(TodoKeys.listDeleteDone));
    await settle(tester);
    await tester.tap(find.byKey(CoreKeys.editSave));
    await settle(tester);
    expect(find.text('Dishes'), findsNothing);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(find.text('Dishes'), findsOneWidget);
    expect(find.text('Laundry'), findsOneWidget);
    await close(tester);
  });

  // Flutter keeps a note with an action until it is dismissed: "Undo" stood there
  // after the rows were deleted for good, and tapped then, it did nothing.
  testWidgets('undo is only offered while it still works', (tester) async {
    // The deletion waits a little longer than "Undo" shows.
    final container = ProviderContainer(
      retry: noRetry,
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);
    expect(
      container.read(todoRepositoryProvider).deleteGrace,
      greaterThan(UndoWindow.fallback),
    );
    await open(tester);
    await tester.tap(find.byKey(TodoKeys.listDeleteDone));
    await settle(tester);
    expect(find.text('Undo'), findsOneWidget);

    await tester.pump(UndoWindow.fallback);
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
    await close(tester);
  });
}
