import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/app/router.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// **Without a calendar, the empty calendar offers one** — it offered a new event,
/// whose sheet had no calendar to pick.
void main() {
  testWidgets('"New calendar" opens its sheet on the calendars', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        overrides: [
          sessionFrom(const SessionState(stage: .localOnly)),
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
    Future<void> settle() async {
      for (int i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
        .read(routerProvider)
        .go('/calendar');
    await settle();

    // No "Event": it would have nowhere to go.
    expect(find.widgetWithText(FloatingActionButton, 'Event'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'New calendar'));
    await settle();

    expect(find.text('Manage calendars'), findsOneWidget);
    // The sheet is open: its title beside the screen's own "New calendar".
    expect(find.text('New calendar'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  // A subscribed calendar takes no events: "Event" opened a sheet with nothing to pick.
  testWidgets('with only a subscribed calendar, the button offers a calendar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final seed = ProviderContainer(
      retry: noRetry,
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
        deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
      ],
    );
    await tester.runAsync(
      () => seed
          .read(calendarRepositoryProvider)
          .createSubscription(
            name: 'Holidays',
            url: 'https://holidays.example/de.ics',
            colorToken: ColorTokens.green,
            syncInterval: 'DAILY',
            targetKind: 'EVENT',
          ),
    );
    seed.dispose();
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        overrides: [
          sessionFrom(const SessionState(stage: .localOnly)),
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
    Future<void> settle() async {
      for (int i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
        .read(routerProvider)
        .go('/calendar');
    await settle();

    expect(find.widgetWithText(FloatingActionButton, 'Event'), findsNothing);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Calendar'));
    await settle();

    expect(find.text('Manage calendars'), findsOneWidget);
    expect(find.text('New calendar'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
