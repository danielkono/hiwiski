import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/router.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:hiwiski/features/account/account/view/account_screen.dart';
import 'package:hiwiski/features/account/view/account_keys.dart';
import 'package:hiwiski/features/session/server_address/server_address_view_model.dart';
import 'package:hiwiski/features/session/server_address/view/server_address_screen.dart';
import 'package:hiwiski/features/session/view/session_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'a11y/a11y_world.dart';
import 'a11y/screens_a11y_test.dart' show settle, unmount;
import 'support/fakes.dart';

/// What the screens offer without a server: no button that only produces an error,
/// and the ways to a server and back.
void main() {
  setUp(mockPlugins);
  tearDown(unmockPlugins);

  Future<void> show(
    WidgetTester tester,
    SessionState session,
    Widget screen,
  ) async {
    final world = (await tester.runAsync(
      () => A11yWorld.create(session: session),
    ))!;
    addTearDown(() async {
      await unmount(tester);
      await tester.runAsync(world.close);
    });
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      a11yApp(overrides: world.overrides(session), home: screen),
    );
    await settle(tester);
  }

  testWidgets('the first start offers the app without a server', (
    tester,
  ) async {
    await show(tester, firstStartSession, const ServerAddressScreen());

    expect(find.byKey(SessionKeys.startLocal), findsOneWidget);
    await unmount(tester);
  });

  test('in the browser there is no app without a server', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      retry: noRetry,
      overrides: [
        sessionFrom(firstStartSession),
        localSettingsProvider.overrideWithValue(settings),
        databaseProvider.overrideWithValue(db),
        servedWebAppProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(serverAddressViewModelProvider).offerLocal, isFalse);
  });

  testWidgets('without a server the account connects and deletes', (
    tester,
  ) async {
    await show(tester, localSession, const AccountScreen());
    final l = await L.delegate.load(const Locale('en'));

    expect(find.byKey(AccountKeys.localConnect), findsOneWidget);
    expect(find.byKey(AccountKeys.localDelete), findsOneWidget);
    expect(find.text(l.accountSignOut), findsNothing);
    expect(find.text(l.familyTitle), findsNothing);
    expect(find.text(l.devicesTitle), findsNothing);
    expect(find.text(l.accountLocal), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('without a server, what needs one leads to the account', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        overrides: [
          sessionFrom(localSession),
          databaseProvider.overrideWithValue(db),
          localSettingsProvider.overrideWithValue(settings),
          deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            theme: HiwiskiTheme.light(),
            localizationsDelegates: const [
              L.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: L.supportedLocales,
            locale: const Locale('en'),
            routerConfig: ref.watch(routerProvider),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final router = container.read(routerProvider);
    String at() => router.routeInformationProvider.value.uri.path;

    for (final path in ['/account/family', '/account/devices', '/password']) {
      router.go(path);
      await tester.pump();
      await tester.pump();
      expect(at(), equals('/account'), reason: path);
    }
    // The server address stays: from there the device connects.
    router.go('/server');
    await tester.pump();
    await tester.pump();
    expect(at(), equals('/server'));
    // Signing in is for whoever has a server.
    router.go('/sign-in');
    await tester.pump();
    await tester.pump();
    expect(at(), equals('/'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
