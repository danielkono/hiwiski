import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/features/todo/new_list/view/new_list_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hiwiski/domain/links/link_index.dart';
import 'package:hiwiski/app/link_index.dart';
import 'package:hiwiski/components/rich_text/view/markdown_toolbar.dart';
import 'package:hiwiski/components/rich_text/view/rich_text_keys.dart';

/// **A new list's description suggests links like every other description.**
///
/// When testing, `#` in "New list" suggested nothing — only editing the list later did.
void main() {
  late HiwiskiDatabase db;
  late LocalSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await LocalSettings.open();
    db = HiwiskiDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  // Not `pumpAndSettle`: the sheet shows progress indicators while providers load.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('typing # in the description suggests items', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          localSettingsProvider.overrideWithValue(settings),
          linkIndexProvider.overrideWithValue(
            LinkIndex.from(const [
              LinkItem(
                itemType: 'WIKI_PAGE',
                itemId: 'w1',
                title: 'Packliste Urlaub',
                entityKey: 'WIKI-3',
              ),
            ]),
          ),
        ],
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
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showNewListSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);

    // Written like a wiki page: the insert bar above the description — without the
    // image button, as the list does not exist yet.
    expect(find.byType(MarkdownToolbar), findsOneWidget);
    expect(find.byKey(RichTextKeys.insertImages), findsNothing);

    final description = find.byKey(const ValueKey('list-description'));
    await tester.tap(description);
    await tester.enterText(description, 'siehe #pack');
    await settle(tester);

    expect(find.text('Packliste Urlaub'), findsOneWidget);
    await tester.tap(find.text('Packliste Urlaub'));
    await settle(tester);

    final field = tester.widget<TextField>(description);
    expect(field.controller!.text, equals('siehe #WIKI-3 '));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
