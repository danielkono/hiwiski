import 'package:drift/native.dart';
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
import 'package:hiwiski/core/theme/hiwiski_symbols.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/components/rich_text/view/markdown_toolbar.dart';
import 'package:hiwiski/features/todo/detail/view/todo_detail_screen.dart';
import 'package:hiwiski/features/todo/view/todo_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **A task's description is written like a wiki page**: on the page, with the
/// insert bar above it — and read with its boxes to tick.
void main() {
  late HiwiskiDatabase db;
  late LocalSettings settings;
  late String todoId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await LocalSettings.open();
    db = HiwiskiDatabase(NativeDatabase.memory());
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

  testWidgets('written in place with the insert bar, read with its boxes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          localSettingsProvider.overrideWithValue(settings),
        ],
      );
      final todos = container.read(todoRepositoryProvider);
      final listId = await todos.createList(
        name: 'Haus',
        kind: ListKinds.standard,
      );
      todoId = await todos.createTodo(listId: listId, title: 'Regal bauen');
      container.dispose();
    });
    tester.view.physicalSize = const Size(900, 1200);
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
          home: Scaffold(body: TodoDetailScreen(todoId: todoId)),
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.text('Edit'));
    await settle(tester);
    expect(find.byType(MarkdownToolbar), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.enterText(
      find.byKey(TodoKeys.todoDescription),
      '- [ ] Schrauben kaufen',
    );
    await tester.tap(find.byKey(CoreKeys.editSave));
    await settle(tester);

    expect(find.byType(MarkdownToolbar), findsNothing);
    expect(find.textContaining('Schrauben kaufen'), findsOneWidget);
    // The box can be ticked right there, as on a page.
    await tester.tap(find.byIcon(HiwiskiSymbols.checkBoxOutlineBlank).last);
    await settle(tester);
    expect(find.byIcon(HiwiskiSymbols.checkBox), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
