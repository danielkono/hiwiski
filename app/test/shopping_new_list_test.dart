import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/wiki/wiki_models.dart';
import 'package:hiwiski/features/wiki/recipe_shopping/view/recipe_shopping_sheet.dart';
import 'package:hiwiski/features/wiki/view/wiki_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hiwiski/app/repositories.dart';

/// **"New shopping list" can be chosen while lists exist.** The first list was set as
/// the default on every build, so the choice snapped straight back to it.
void main() {
  testWidgets('choosing a new list shows its name field', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
        deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
      ],
    );
    addTearDown(container.dispose);
    final page = (await tester.runAsync(() async {
      await container
          .read(todoRepositoryProvider)
          .createList(name: 'Groceries', kind: ListKinds.shopping);
      final id = await container
          .read(wikiRepositoryProvider)
          .createPage(title: 'Pumpkin soup', kind: PageKinds.recipe);
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
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRecipeShoppingSheet(
                  context,
                  page: page,
                  ingredients: const [Ingredient(label: 'Pumpkin')],
                  servings: 4,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.byKey(WikiKeys.newShoppingList), findsNothing);

    await tester.tap(find.text('New shopping list'));
    await tester.pump();

    expect(find.byKey(WikiKeys.newShoppingList), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
