import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/wiki/wiki_models.dart';
import 'package:hiwiski/domain/wiki/wiki_page.dart';
import 'package:hiwiski/features/wiki/page/view/recipe/recipe_kind.dart';
import 'package:hiwiski/features/wiki/view/wiki_keys.dart';

/// **While a recipe is edited its ingredients move by drag and drop**, by the grip
/// at the start of each row.
void main() {
  testWidgets('a row dragged by its grip takes another place', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final draft = RecipeDraft(
      WikiPage(
        id: 'r1',
        ownerId: 'anna',
        version: 1,
        position: 0,
        kind: PageKinds.recipe,
        title: 'Pancakes',
        content: '',
        properties: jsonEncode({
          'ingredients': [
            for (final label in ['Flour', 'Milk', 'Eggs'])
              Ingredient(label: label).toJson(),
          ],
        }),
        tags: '',
      ),
    );
    addTearDown(draft.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: HiwiskiTheme.light(),
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: L.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: draft,
            builder: (context, _) => ListView(children: draft.fields(context)),
          ),
        ),
      ),
    );
    double top(String label) => tester.getTopLeft(find.text(label)).dy;
    expect(top('Flour'), lessThan(top('Milk')));

    final rowHeight = top('Milk') - top('Flour');
    final grip = await tester.startGesture(
      tester.getCenter(find.byKey(WikiKeys.recipeIngredientHandle(0))),
    );
    await tester.pump(const Duration(milliseconds: 50));
    for (int i = 0; i < 10; i++) {
      await grip.moveBy(Offset(0, rowHeight * 0.25));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await grip.up();
    await tester.pumpAndSettle();

    expect(top('Milk'), lessThan(top('Eggs')));
    expect(top('Eggs'), lessThan(top('Flour')));
  });
}
