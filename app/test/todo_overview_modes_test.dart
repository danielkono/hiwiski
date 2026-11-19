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
import 'package:hiwiski/features/todo/overview/view/todo_overview_screen.dart';
import 'package:hiwiski/features/todo/view/todo_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **The task overview has a view, as the calendar does**: together, by kind, or as
/// a list with the chosen list open next to it.
void main() {
  late HiwiskiDatabase db;
  late LocalSettings settings;
  late Map<String, String> ids;

  setUp(() async {
    db = HiwiskiDatabase(NativeDatabase.memory());
    ids = {};
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, String view) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({'hiwiski.todo.view': view});
      settings = await LocalSettings.open();
      final container = ProviderContainer(
        retry: noRetry,
        overrides: [
          databaseProvider.overrideWithValue(db),
          localSettingsProvider.overrideWithValue(settings),
        ],
      );
      final todos = container.read(todoRepositoryProvider);
      ids['Chores'] = await todos.createList(
        name: 'Chores',
        kind: ListKinds.standard,
      );
      ids['Groceries'] = await todos.createList(
        name: 'Groceries',
        kind: ListKinds.shopping,
      );
      container.dispose();
    });
    tester.view.physicalSize = const Size(1300, 900);
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
          home: const TodoOverviewScreen(),
        ),
      ),
    );
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  testWidgets('by kind, each kind has its titled group', (tester) async {
    await pump(tester, 'BY_KIND');

    // "Tasks" is the page's title too.
    Finder inGroups(String text) => find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.text(text),
    );
    expect(inGroups('Tasks'), findsOneWidget);
    expect(inGroups('Shopping'), findsOneWidget);
    expect(
      tester.getTopLeft(inGroups('Tasks')).dy,
      lessThan(tester.getTopLeft(inGroups('Shopping')).dy),
    );
    await unmount(tester);
  });

  testWidgets('as a list, the chosen list opens next to the rows', (
    tester,
  ) async {
    await pump(tester, 'SIDEBAR');

    final chores = find.byKey(TodoKeys.overviewRow(ids['Chores']!));
    final groceries = find.byKey(TodoKeys.overviewRow(ids['Groceries']!));
    expect(chores, findsOneWidget);
    expect(groceries, findsOneWidget);
    // The first list is open: its name stands a second time, in its own header.
    expect(find.text('Chores'), findsNWidgets(2));

    await tester.tap(groceries);
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Groceries'), findsNWidgets(2));
    expect(find.text('Chores'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the rows can be put away and brought back', (tester) async {
    await pump(tester, 'SIDEBAR');
    final chores = find.byKey(TodoKeys.overviewRow(ids['Chores']!));
    expect(chores, findsOneWidget);

    await tester.tap(find.byKey(TodoKeys.overviewRowsHide));
    await tester.pump();
    expect(chores, findsNothing);
    // The list stays open, now across the whole width.
    expect(find.text('Chores'), findsOneWidget);
    // Its button sits left of the list's title, not in a column of its own.
    final show = find.byKey(TodoKeys.overviewRowsShow);
    final title = find.text('Chores');
    expect(tester.getCenter(show).dx, lessThan(tester.getTopLeft(title).dx));
    expect(
      (tester.getCenter(show).dy - tester.getCenter(title).dy).abs(),
      lessThan(24),
    );

    await tester.tap(find.byKey(TodoKeys.overviewRowsShow));
    await tester.pump();
    expect(chores, findsOneWidget);
    await unmount(tester);
  });
}
