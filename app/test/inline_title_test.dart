import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

/// **Held, a task's title is edited right in its row** — no dialog, no sheet.
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

  /// Lets the database's writes and streams through, which run on the real clock.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpList(WidgetTester tester) async {
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
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  Future<String> titleInDb(WidgetTester tester) async => (await tester.runAsync(
    () => (db.select(db.todos)..where((t) => t.id.equals(todoId))).getSingle(),
  ))!.title;

  testWidgets('a long press opens the title as a field in the row, Enter '
      'saves it', (tester) async {
    await pumpList(tester);

    await tester.longPress(find.text('Clean windows'));
    await settle(tester);

    final field = find.byKey(ValueKey('title-field-$todoId'));
    expect(field, findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.enterText(field, 'Clean all windows');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(field, findsNothing);
    expect(find.text('Clean all windows'), findsOneWidget);
    expect(await titleInDb(tester), equals('Clean all windows'));
    await unmount(tester);
  });

  testWidgets('Escape keeps the old title', (tester) async {
    await pumpList(tester);

    await tester.longPress(find.text('Clean windows'));
    await settle(tester);
    final field = find.byKey(ValueKey('title-field-$todoId'));
    await tester.enterText(field, 'Something else');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    expect(field, findsNothing);
    expect(find.text('Clean windows'), findsOneWidget);
    expect(await titleInDb(tester), equals('Clean windows'));
    await unmount(tester);
  });
}
