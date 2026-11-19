import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/features/wiki/view/wiki_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hiwiski/app/repositories.dart';

import 'support/page_host.dart';

/// **"Saved on leaving" saves.** It saved in `dispose` through `ref`, which Riverpod
/// no longer allows there: it threw, and what was typed was lost.
void main() {
  testWidgets('leaving a page while editing keeps what was typed', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      retry: noRetry,
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
        deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
      ],
    );
    addTearDown(container.dispose);
    final page = (await tester.runAsync(() async {
      final id = await container
          .read(wikiRepositoryProvider)
          .createPage(title: 'Packing list');
      return await container.read(wikiRepositoryProvider).watchPage(id).first;
    }))!;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
          home: Scaffold(body: PageHost(page: page)),
        ),
      ),
    );
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Edit'));
    await tester.pump();
    await tester.enterText(find.byKey(WikiKeys.wikiContent), 'Sunscreen');
    // An emptied title is not saved.
    await tester.enterText(find.byKey(WikiKeys.wikiTitle), '  ');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);

    final row = (await tester.runAsync(
      () => db.select(db.wikiPages).getSingle(),
    ))!;
    expect(row.content, equals('Sunscreen'));
    expect(row.title, equals('Packing list'));
  });
}
