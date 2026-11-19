import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/features/todo/checklist/view/checklist_screen.dart';
import 'package:hiwiski/features/todo/view/list_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **"Undo" brings a task deleted from its row back** — in the task list too, where
/// the row that offered it is gone by the time "Undo" is tapped.
void main() {
  late HiwiskiDatabase db;
  late LocalSettings settings;
  late String listId;
  late String todoId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await LocalSettings.open();
    db = HiwiskiDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      retry: noRetry,
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
      ],
    );
    final todos = container.read(todoRepositoryProvider);
    listId = await todos.createList(name: 'Chores', kind: ListKinds.standard);
    todoId = await todos.createTodo(listId: listId, title: 'Clean windows');
    container.dispose();
  });

  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('undo in the task list brings the task back', (tester) async {
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
    expect(find.text('Clean windows'), findsOneWidget);

    final press = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey('delete-todo-$todoId'))),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await press.up();
    await settle(tester);
    expect(find.text('Clean windows'), findsNothing);

    await tester.tap(find.text('Undo'));
    await settle(tester);

    expect(find.text('Clean windows'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  // On the phone the info area sits below the rows; an empty list left it out, and
  // with it renaming, archiving, deleting and turning it into a board.
  testWidgets('an empty list on the phone still has its info area', (
    tester,
  ) async {
    final emptyId = (await tester.runAsync(() async {
      final container = ProviderContainer(
        retry: noRetry,
        overrides: [
          databaseProvider.overrideWithValue(db),
          localSettingsProvider.overrideWithValue(settings),
        ],
      );
      final id = await container
          .read(todoRepositoryProvider)
          .createList(name: 'Empty', kind: ListKinds.standard);
      container.dispose();
      return id;
    }))!;
    tester.view.physicalSize = const Size(390, 1400);
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
          home: ChecklistScreen(listId: emptyId),
        ),
      ),
    );
    await settle(tester);

    expect(find.byType(ListInfo), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
