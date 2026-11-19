import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/ui/ui_keys.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/features/todo/checklist/view/checklist_screen.dart';
import 'package:hiwiski/features/todo/detail/view/todo_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **A task list is sorted by dragging**, as the shopping list and the board are:
/// held, moved and dropped on a row, a task goes before or after it. And **a task's
/// title is edited on its page**, not in a dialog over it.
void main() {
  late HiwiskiDatabase db;
  late LocalSettings settings;
  late String listId;
  late String firstId;

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
    firstId = await todos.createTodo(listId: listId, title: 'Alpha');
    await todos.createTodo(listId: listId, title: 'Bravo');
    await todos.createTodo(listId: listId, title: 'Charlie');
    container.dispose();
  });

  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
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
          home: home,
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  Future<List<String>> order(WidgetTester tester) async {
    final rows = (await tester.runAsync(
      () => (db.select(
        db.todos,
      )..orderBy([(row) => OrderingTerm.asc(row.position)])).get(),
    ))!;
    return [for (final row in rows) row.title];
  }

  testWidgets('a task dropped on the upper half of another goes before it', (
    tester,
  ) async {
    await pump(tester, ChecklistScreen(listId: listId));
    expect(await order(tester), equals(['Alpha', 'Bravo', 'Charlie']));

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Charlie')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    final alpha = tester.getRect(find.text('Alpha'));
    final target = Offset(alpha.center.dx, alpha.top);
    for (int i = 1; i <= 10; i++) {
      final from = tester.getCenter(find.text('Charlie').first);
      await gesture.moveTo(Offset.lerp(from, target, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settle(tester);

    expect(await order(tester), equals(['Charlie', 'Alpha', 'Bravo']));
    await unmount(tester);
  });

  testWidgets('"Edit" opens the title of a task as a field on the page', (
    tester,
  ) async {
    await pump(tester, TodoDetailScreen(todoId: firstId));

    await tester.tap(find.text('Edit'));
    await settle(tester);
    final field = find.byKey(const ValueKey('todo-title-field'));
    expect(field, findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(Dialog), findsNothing);

    await tester.enterText(field, 'Alpha one');
    await tester.tap(find.byKey(CoreKeys.editSave));
    await settle(tester);

    expect(field, findsNothing);
    final rows = (await tester.runAsync(() => db.select(db.todos).get()))!;
    expect(
      rows.firstWhere((row) => row.id == firstId).title,
      equals('Alpha one'),
    );
    await unmount(tester);
  });
}
