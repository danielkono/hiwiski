import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/common/wire.dart';
import '../../../../../core/l10n/generated/app_localizations.dart';
import '../../../../../core/routing/item_navigation.dart';
import '../../../../../core/routing/routes.dart';
import '../../../../../core/theme/hiwiski_metrics.dart';
import '../../../../../core/theme/hiwiski_symbols.dart';
import '../../../../../core/theme/hiwiski_tokens.dart';
import '../../../../../domain/wiki/wiki_models.dart';
import '../../../../../domain/wiki/wiki_page.dart';
import '../../page_view_model.dart';
import '../page_kind.dart';
import 'recipe_grid.dart';

/// Above a recipe collection's text: its recipes as a card grid — or, while it has none, a word that says so and the first recipe.
class RecipeFolderHead extends ConsumerWidget {
  const RecipeFolderHead({
    super.key,
    required this.page,
    required this.state,
    required this.actions,
  });

  /// Whether [page] has a head: recipes below it, or it is an empty collection.
  static bool shows(WikiPage page, PageState state) =>
      state.recipes.isNotEmpty || page.kind == kindRecipeFolder;

  final WikiPage page;
  final PageState state;
  final PageKindActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final recipes = state.recipes;
    if (recipes.isNotEmpty) {
      return Padding(
        padding: const .only(bottom: HiwiskiMetrics.space24),
        child: RecipeGrid(
          pageId: page.id,
          recipes: recipes,
          onOpen: (recipe) => actions.preview
              ? openPreviewOf(
                  context,
                  ref,
                  itemType: EntityTypes.wikiPage,
                  itemId: recipe.id,
                )
              : WikiRoute(pageId: recipe.id).go(context),
        ),
      );
    }
    // An empty collection says so and offers the first recipe — the import is not
    // the only way in.
    final onCreate = actions.onCreate;
    final onImport = actions.onImport;
    return Padding(
      padding: const .only(bottom: HiwiskiMetrics.space24),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Text(
            l.recipeFolderEmpty,
            style: context.texts.bodyMedium?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
          if (onCreate != null && actions.writable && !actions.preview) ...[
            const SizedBox(height: HiwiskiMetrics.space12),
            Wrap(
              spacing: HiwiskiMetrics.space8,
              runSpacing: HiwiskiMetrics.space8,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(HiwiskiSymbols.restaurant),
                  label: Text(l.wikiNewRecipe),
                  onPressed: () => onCreate(page.id, PageKinds.recipe),
                ),
                if (onImport != null)
                  OutlinedButton.icon(
                    icon: const Icon(HiwiskiSymbols.download),
                    label: Text(l.recipeImportAction),
                    onPressed: () => onImport(page.id),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
