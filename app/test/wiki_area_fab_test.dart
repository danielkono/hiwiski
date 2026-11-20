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
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/features/wiki/area/view/wiki_area_screen.dart';
import 'package:hiwiski/features/wiki/view/wiki_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/floating_button.dart';

/// **The wiki's "New page" button does not animate**, like the buttons of the tasks
/// and the calendar: it is there with the tree, and when a page is opened in place
/// on the phone the button goes and comes back with no transition.
void main() {
  testWidgets('the button comes with the tree and returns with it in full', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(400, 800);
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
    final id = await tester.runAsync(
      () => container
          .read(wikiRepositoryProvider)
          .createPage(title: 'Packing list'),
    );
    // Opened by an address, as a reference chip does: the same screen, its page
    // changed in place.
    final opened = ValueNotifier<String?>(null);
    addTearDown(opened.dispose);

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
          home: ValueListenableBuilder(
            valueListenable: opened,
            builder: (context, id, _) => WikiAreaScreen(initialPageId: id),
          ),
        ),
      ),
    );
    final button = find.byKey(WikiKeys.newPage);
    // Pumped a millisecond at a time: a button that grows in is still small in
    // the first frame it shows up in.
    for (int i = 0; i < 100 && button.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(button, findsOneWidget);
    expect(shownInFull(tester, button), isTrue);

    opened.value = id;
    await tester.pump(const Duration(milliseconds: 1));
    expect(button, findsNothing);

    opened.value = null;
    await tester.pump(const Duration(milliseconds: 1));
    expect(button, findsOneWidget);
    expect(shownInFull(tester, button), isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
