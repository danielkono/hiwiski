import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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

/// **"More fields" opens a sheet over the list**, like a new event — it was a page of
/// its own, and after it the task's page.
void main() {
  testWidgets('the sheet takes what was typed and leaves the list in place', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final settings = (await tester.runAsync(LocalSettings.open))!;
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      retry: noRetry,
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);
    final listId = (await tester.runAsync(
      () => container
          .read(todoRepositoryProvider)
          .createList(name: 'Chores', kind: ListKinds.standard),
    ))!;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: L.localizationsDelegates,
          supportedLocales: L.supportedLocales,
          locale: const Locale('en'),
          home: ChecklistScreen(listId: listId),
        ),
      ),
    );
    Future<void> settle() async {
      for (int i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    await tester.enterText(find.byType(TextField).last, 'Clean windows');
    await tester.tap(find.byTooltip('More fields'));
    await settle();

    // The sheet, over the list, with the title typed so far.
    expect(find.text('New task'), findsOneWidget);
    expect(find.byType(ChecklistScreen), findsOneWidget);
    // The quick entry below still holds it; the sheet's title starts with it.
    expect(find.widgetWithText(TextField, 'Clean windows'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('new-todo-create')));
    await settle();

    expect(find.text('New task'), findsNothing);
    expect(find.byType(ChecklistScreen), findsOneWidget);
    // The row; the quick entry is empty again.
    expect(find.text('Clean windows'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
