import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_symbols.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/features/wiki/area/view/wiki_area_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// **Beside its tree a wiki page is laid out as a list is beside the task lists**: the
/// area's header keeps saying "Wiki", the page's title stands under it — and the
/// button that brings the tree back stands where the one that put it away stood.
void main() {
  testWidgets('the area keeps its title, and the tree button its place', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      retry: noRetry,
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
        deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
        sessionAt(signedInAnna),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container
          .read(wikiRepositoryProvider)
          .createPage(title: 'Packing list'),
    );

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
          home: const WikiAreaScreen(),
        ),
      ),
    );
    for (int i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The area's title above, the page's title below it and to the right of the
    // tree — once each, besides the page's row in the tree.
    final area = tester.getRect(find.text('Wiki'));
    final title = tester.getRect(find.text('Packing list').last);
    expect(title.top, greaterThan(area.bottom));
    expect(find.text('Edit'), findsOneWidget);

    final hide = tester.getRect(find.byIcon(HiwiskiSymbols.leftPanelClose));
    await tester.tap(find.byIcon(HiwiskiSymbols.leftPanelClose));
    await tester.pump();
    final show = tester.getRect(find.byIcon(HiwiskiSymbols.leftPanelOpen));
    expect(show, equals(hide));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
