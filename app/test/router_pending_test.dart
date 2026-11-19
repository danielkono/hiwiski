import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/app/router.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// **A link survives a refused remembered session.** A remembered session starts
/// signed in; when the handshake then refused it, the router sent to sign-in and the
/// link was gone — after signing in it went to start.
void main() {
  testWidgets('after signing in again, the link opens', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionFrom(_session),
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
    router.go('/search');
    await tester.pump();
    await tester.pump();

    final session = container.read(sessionStoreProvider);
    void set(SessionStage stage) =>
        session.debugValue = session.value.copyWith(stage: stage);
    set(SessionStage.signedOut);
    await tester.pump();
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, equals('/sign-in'));

    set(SessionStage.signedIn);
    await tester.pump();
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, equals('/search'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  // A mistyped address on the web showed Flutter's own error page.
  testWidgets('an address without a screen says so and leads to the start', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionFrom(_session),
          databaseProvider.overrideWithValue(db),
          localSettingsProvider.overrideWithValue(settings),
          deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            theme: HiwiskiTheme.light(),
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            locale: const Locale('en'),
            routerConfig: ref.watch(routerProvider),
          ),
        ),
      ),
    );
    final router = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    ).read(routerProvider);
    router.go('/account/devicses');
    await tester.pump();
    await tester.pump();

    expect(find.text('This page does not exist.'), findsOneWidget);
    await tester.tap(find.text('Go to Home'));
    await tester.pump();
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, equals('/'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}

const _session = SessionState(
  stage: .signedIn,
  serverAddress: 'http://hiwiski.test',
);
