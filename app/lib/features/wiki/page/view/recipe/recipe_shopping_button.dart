import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/l10n/generated/app_localizations.dart';
import '../../../../../core/theme/hiwiski_metrics.dart';
import '../../../../../core/theme/hiwiski_symbols.dart';
import '../../../../../domain/wiki/wiki_page.dart';
import '../../../recipe_shopping/view/recipe_shopping_sheet.dart';
import '../../page_view_model.dart';

/// "Add to shopping list" — on the phone as a docked button at the bottom, on the
/// desktop sticky at the end of the column.
class RecipeShoppingButton extends ConsumerWidget {
  const RecipeShoppingButton({super.key, required this.page});

  final WikiPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final state = ref.watch(pageViewModelProvider(page.id)).value;
    return SizedBox(
      height: HiwiskiMetrics.buttonHeight,
      child: FilledButton.icon(
        icon: const Icon(HiwiskiSymbols.addShoppingCart),
        label: Text(l.recipeToShoppingList),
        onPressed: switch (state) {
          final state? when state.scaledIngredients.isNotEmpty =>
            () => showRecipeShoppingSheet(
              context,
              page: page,
              ingredients: state.scaledIngredients,
              servings: state.shownServings,
            ),
          _ => null,
        },
      ),
    );
  }
}
