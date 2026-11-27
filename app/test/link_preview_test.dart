import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/components/links/view/link_preview.dart';
import 'package:hiwiski/core/routing/item_navigation.dart';
import 'package:hiwiski/core/routing/leave_for_target.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/core/ui/ui_keys.dart';
import 'package:drift/native.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hiwiski/domain/links/link_index.dart';
import 'package:hiwiski/app/link_index.dart';

/// **A link opens a preview over the page; "Open" goes to the full one, and "Back"
/// there returns to the page the link was on**.
void main() {
  const router = LinkItem(
    itemType: 'WIKI_PAGE',
    itemId: 'p2',
    title: 'Router',
    entityKey: 'WIKI-3',
  );

  Widget app(Widget home, {List overrides = const []}) => ProviderScope(
    retry: noRetry,
    overrides: [...overrides],
    child: MaterialApp(
      theme: HiwiskiTheme.light(),
      localizationsDelegates: const [
        L.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: L.supportedLocales,
      locale: const Locale('en'),
      home: home,
    ),
  );

  testWidgets('the preview shows the target, "Open" asks for the full page', (
    tester,
  ) async {
    int opened = 0;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showLinkPreview(
                context,
                target: router,
                body: const Text('Password is on the back.'),
                onOpenFull: () => opened++,
              ),
              child: const Text('link'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('link'));
    await tester.pumpAndSettle();

    expect(find.text('Router'), findsOneWidget);
    expect(find.text('WIKI-3'), findsOneWidget);
    expect(find.text('Password is on the back.'), findsOneWidget);

    await tester.tap(find.byKey(CoreKeys.linkPreviewOpen));
    expect(opened, equals(1));

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Router'), findsNothing);
    expect(find.text('link'), findsOneWidget);
  });

  group("a list's preview is its page without the info bar", () {
    late HiwiskiDatabase db;
    late LocalSettings settings;
    late String listId;

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
      final repository = container.read(todoRepositoryProvider);
      listId = await repository.createList(
        name: 'Household',
        kind: 'STANDARD',
        description: 'What the flat needs.',
      );
      await repository.createTodo(listId: listId, title: 'Descale kettle');
      container.dispose();
    });

    tearDown(() => db.close());

    Future<void> settle(WidgetTester tester) async {
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('rows can be ticked, a row opens its own preview', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            localSettingsProvider.overrideWithValue(settings),
            deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
          ],
          Consumer(
            builder: (context, ref, _) {
              // Subscribed, so the link index has the task when its row is tapped.
              ref.watch(linkIndexProvider);
              return Scaffold(
                body: TextButton(
                  onPressed: () => openLinkTarget(
                    context,
                    ref,
                    LinkItem(
                      itemType: 'TODO_LIST',
                      itemId: listId,
                      title: 'Household',
                    ),
                  ),
                  child: const Text('link'),
                ),
              );
            },
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('link'));
      await settle(tester);

      expect(find.text('What the flat needs.'), findsOneWidget);
      expect(find.text('Descale kettle'), findsOneWidget);
      // No quick entry: nothing is added in a preview.
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.byTooltip('Done'));
      await settle(tester);
      final todos = await db.select(db.todos).get();
      expect(todos.single.status, equals('DONE'));

      // The row opens the task's preview on top — its title not editable there.
      await tester.tap(find.text('Descale kettle'));
      await settle(tester);
      expect(find.text('Descale kettle'), findsNWidgets(3));
      expect(find.text('Add description'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    });
  });

  testWidgets('"Back" on a pushed target returns, otherwise to the parent', (
    tester,
  ) async {
    final routes = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('parent')),
        GoRoute(path: '/origin', builder: (_, _) => const Text('origin')),
        GoRoute(
          path: '/target',
          builder: (context, _) => TextButton(
            onPressed: () => goBack(context, () => context.go('/')),
            child: const Text('back'),
          ),
        ),
      ],
      initialLocation: '/origin',
    );
    addTearDown(routes.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: routes));

    // The route answers nothing; the test looks at what it shows.
    routes.push<void>('/target').ignore();
    await tester.pumpAndSettle();
    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    expect(find.text('origin'), findsOneWidget);

    routes.go('/target');
    await tester.pumpAndSettle();
    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    expect(find.text('parent'), findsOneWidget);
  });

  // On a phone the preview is a bottom sheet on the shell's navigator; "Open" closed
  // only the root's popups and left it under the target.
  testWidgets('"Open" closes the preview inside a shell route', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const note = LinkItem(itemType: 'NOTE', itemId: 'n1', title: 'Shopping');
    final routes = GoRouter(
      routes: [
        ShellRoute(
          builder: (_, _, child) => Scaffold(body: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => openLinkTarget(context, ref, note),
                  child: const Text('link'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        child: MaterialApp.router(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: const [
            L.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: L.supportedLocales,
          locale: const Locale('en'),
          routerConfig: routes,
        ),
      ),
    );
    await tester.tap(find.text('link'));
    await tester.pumpAndSettle();
    expect(find.text('Shopping'), findsWidgets);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('Shopping'), findsNothing);
  });

  // A mind map full screen lies over the shell: a target opened in the shell landed
  // behind it, out of sight. The screen makes way first.
  testWidgets('"Open" from a screen over the shell closes that screen first', (
    tester,
  ) async {
    const note = LinkItem(itemType: 'NOTE', itemId: 'n1', title: 'Shopping');
    final root = GlobalKey<NavigatorState>();
    final routes = GoRouter(
      navigatorKey: root,
      routes: [
        ShellRoute(
          builder: (_, _, child) => Scaffold(body: child),
          routes: [GoRoute(path: '/', builder: (_, _) => const Text('page'))],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        child: MaterialApp.router(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: const [
            L.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: L.supportedLocales,
          locale: const Locale('en'),
          routerConfig: routes,
        ),
      ),
    );
    final navigator = root.currentState!;
    // The pushed screen answers nothing.
    navigator
        .push(
          MaterialPageRoute<void>(
            builder: (context) => LeaveForTarget(
              leave: () => navigator.pop(),
              child: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => TextButton(
                    onPressed: () => openLinkTarget(context, ref, note),
                    child: const Text('map link'),
                  ),
                ),
              ),
            ),
          ),
        )
        .ignore();
    await tester.pumpAndSettle();

    await tester.tap(find.text('map link'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('map link'), findsNothing);
    expect(find.text('Shopping'), findsNothing);
    expect(find.text('page'), findsOneWidget);
  });
}
