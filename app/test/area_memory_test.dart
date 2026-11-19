import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/shell/app_shell.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **Switching areas keeps where one was**: a list open under
/// "Tasks" is open again after a look at the wiki; "Tasks" tapped while there goes to
/// its start. Account → Customize turns it off.
void main() {
  late LocalSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await LocalSettings.open();
  });

  Future<GoRouter> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget page(GoRouterState state) => Text('at ${state.uri}');
    final router = GoRouter(
      initialLocation: '/tasks/list/a',
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              AppShell(location: state.uri.path, child: child),
          routes: [
            GoRoute(path: '/', builder: (_, state) => page(state)),
            GoRoute(path: '/calendar', builder: (_, state) => page(state)),
            GoRoute(
              path: '/tasks',
              builder: (_, state) => page(state),
              routes: [
                GoRoute(path: 'list/:id', builder: (_, state) => page(state)),
              ],
            ),
            GoRoute(path: '/wiki', builder: (_, state) => page(state)),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localSettingsProvider.overrideWithValue(settings)],
        child: MaterialApp.router(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: const [
            L.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: L.supportedLocales,
          locale: const Locale('en'),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  String at(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.toString();

  testWidgets('an area returns to the page it was left on', (tester) async {
    final router = await pump(tester);
    expect(at(router), equals('/tasks/list/a'));

    await tester.tap(find.text('Wiki'));
    await tester.pumpAndSettle();
    expect(at(router), equals('/wiki'));

    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();
    expect(at(router), equals('/tasks/list/a'));

    // Tapped while there: to its start.
    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();
    expect(at(router), equals('/tasks'));
  });

  testWidgets('switched off, an area opens at its start', (tester) async {
    await settings.setKeepAreas(false);
    final router = await pump(tester);

    await tester.tap(find.text('Wiki'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();
    expect(at(router), equals('/tasks'));
  });
}
