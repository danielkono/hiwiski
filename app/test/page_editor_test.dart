import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/ui/ui_keys.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/components/rich_text/view/rich_text_keys.dart';
import 'package:hiwiski/features/wiki/page/page_view_model.dart';
import 'package:hiwiski/features/wiki/view/wiki_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hiwiski/app/repositories.dart';

import 'support/page_host.dart';

/// **Writing a page is writing on a sheet, not into a box**: the text reaches down to the bottom, a tap below it writes on at its end,
/// and comments and info wait until the page is read again.
void main() {
  testWidgets('a tap below the text writes on at its end', (tester) async {
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
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(find.text('Comments'), findsNothing);

    await tester.tap(find.byKey(WikiKeys.wikiContentBelow));
    await tester.pump();

    final field = tester.widget<TextField>(find.byKey(WikiKeys.wikiContent));
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.selection.baseOffset, equals('Sunscreen'.length));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  // "Cancel" stands beside "Save" as on every item: what was typed is gone, and
  // nothing is written.
  testWidgets('"Cancel" leaves the page as it was', (tester) async {
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
    await tester.tap(find.byKey(CoreKeys.editCancel));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byKey(WikiKeys.wikiContent), findsNothing);
    expect(find.text('Edit'), findsOneWidget);
    final saved = await tester.runAsync(
      () => container.read(wikiRepositoryProvider).watchPage(page.id).first,
    );
    expect(saved?.content, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets(
    'while pictures go up, the docked bar stays without the keyboard',
    (tester) async {
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
      await tester.tap(find.byKey(WikiKeys.wikiContent));
      await tester.pump();
      expect(find.byKey(RichTextKeys.insertImages), findsOneWidget);

      final upload = Completer<List<String>>();
      unawaited(
        addContentImagesMutation
            .run(container, (_) => upload.future)
            .then<void>((_) {}, onError: (_) {}),
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(find.byKey(RichTextKeys.imagesBusy), findsOneWidget);

      upload.complete(const []);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(RichTextKeys.insertImages), findsNothing);
      expect(find.byKey(RichTextKeys.imagesBusy), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    },
  );
}
