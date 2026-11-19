import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/app/router.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:hiwiski/features/calendar/manage_calendars/view/manage_calendars_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// **Screens open at once; on iOS a swipe from the edge goes back.** go_router built
/// every page without a transition — it looks for `material_ui`'s `MaterialApp`, not
/// the one the app runs in — and such a page cannot be swiped back. A sliding page,
/// though, was more than wanted: only the swipe moves one.
void main() {
  Future<GoRouter> app(WidgetTester tester) async {
    // A phone: on a wider screen the navigation rail lies along the left edge.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
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
    return container.read(routerProvider);
  }

  // Not pumpAndSettle: the screens keep a progress indicator turning.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  testWidgets('a screen on top opens at once, without sliding in', (
    tester,
  ) async {
    final router = await app(tester);
    await settle(tester);
    router.go('/calendar');
    await settle(tester);

    unawaited(router.push<void>('/calendar/manage'));
    await tester.pump();
    await tester.pump();
    final screen = find.byType(ManageCalendarsScreen);
    expect(screen, findsOneWidget);
    expect(tester.getTopLeft(screen).dx, equals(0));

    await close(tester);
  }, variant: const TargetPlatformVariant({.iOS, .android, .macOS}));

  testWidgets('on iOS a pushed screen is swiped back from the left edge', (
    tester,
  ) async {
    final router = await app(tester);
    router.go('/calendar/manage');
    await settle(tester);
    expect(router.state.uri.path, equals('/calendar/manage'));

    final gesture = await tester.startGesture(const Offset(2, 400));
    for (int i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settle(tester);

    expect(router.state.uri.path, equals('/calendar'));
    await close(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}

const _session = SessionState(
  stage: .signedIn,
  serverAddress: 'http://hiwiski.test',
);
