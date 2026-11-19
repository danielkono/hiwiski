import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/router.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:hiwiski/features/session/view/session_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// **A device that lost its access is locked, not cleared.** The lock screen names
/// whose data it is and what is not on the server yet; signing in again keeps it,
/// deleting asks first.
void main() {
  late HiwiskiDatabase db;
  late LocalSettings settings;

  Future<ProviderContainer> pump(WidgetTester tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      settings = await LocalSettings.open();
    });
    db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionFrom(_locked),
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
    // A change made offline, still waiting.
    await tester.runAsync(
      () => container
          .read(outboxProvider)
          .add(
            entityType: 'TODO_LIST',
            entityId: 'l1',
            op: 'upsert',
            fields: {'name': 'Groceries'},
          ),
    );
    await settle(tester);
    return container;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  String path(ProviderContainer container) =>
      container.read(routerProvider).routeInformationProvider.value.uri.path;

  testWidgets('locked, every page leads to the lock screen', (tester) async {
    final container = await pump(tester);
    container.read(routerProvider).go('/tasks');
    await settle(tester);

    expect(path(container), equals('/access-lost'));
    expect(find.text('Access lost'), findsOneWidget);
    expect(find.textContaining('Anna'), findsOneWidget);
    expect(
      find.textContaining('1 change is not on the server'),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('signing in again starts as the same member', (tester) async {
    final container = await pump(tester);

    await tester.tap(find.byKey(SessionKeys.signInAgain));
    await settle(tester);

    expect(path(container), equals('/sign-in'));
    final username = tester.widget<TextField>(
      find.byKey(SessionKeys.loginUsername),
    );
    expect(username.controller?.text, equals('anna'));
    expect(find.textContaining('Sign in as Anna'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('deleting asks, then clears the device', (tester) async {
    final container = await pump(tester);

    await tester.tap(find.byKey(SessionKeys.discardData));
    await settle(tester);
    expect(find.textContaining('1 change that is not on the server'), findsOne);

    await tester.tap(find.byKey(SessionKeys.discardConfirm));
    await settle(tester);

    expect(
      container.read(sessionProvider).stage,
      equals(SessionStage.signedOut),
    );
    final outbox = await tester.runAsync(
      () => db.select(db.outboxEntries).get(),
    );
    expect(outbox, isEmpty);
    await unmount(tester);
  });
}

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _locked = SessionState(
  stage: .accessLost,
  serverAddress: 'http://hiwiski.test',
  session: Session(
    member: Member(
      id: 'anna',
      username: 'anna',
      displayName: 'Anna',
      isAdmin: false,
      colorToken: .blue,
    ),
    deviceId: 'device-1',
    mustChangePassword: false,
  ),
);
