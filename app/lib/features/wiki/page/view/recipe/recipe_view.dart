import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/l10n/generated/app_localizations.dart';
import '../../../../../core/theme/hiwiski_metrics.dart';
import '../../../../../core/theme/hiwiski_symbols.dart';
import '../../../../../core/theme/hiwiski_tokens.dart';
import '../../../../../domain/wiki/wiki_models.dart';
import '../../../../../domain/wiki/wiki_page.dart';
import '../../page_view_model.dart';
import '../text/text_blocks.dart';
import 'recipe_image.dart';

/// A recipe.
///
/// Image on the left (240 high, radius 20), details on the right: **servings as a row
/// with −/+** on `sf2`, the ingredient amounts follow along; ingredients as a two-column
/// grid (amount 80 wide, bold / product); preparation as running text. On a narrow
/// screen the image sits at the top.
class RecipeView extends ConsumerWidget {
  const RecipeView({super.key, required this.page, this.writable = true});

  final WikiPage page;

  /// Whether the reader may change the recipe — the image picker sits on the image only then.
  final bool writable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pageViewModelProvider(page.id)).value;
    if (state == null) return const SizedBox.shrink();
    final l = L.of(context);
    final scaled = state.scaledIngredients;
    final shown = state.shownServings;
    final viewModel = ref.watch(pageViewModelProvider(page.id).notifier);

    final ingredients = Column(
      crossAxisAlignment: .stretch,
      children: [
        Container(
          padding: const .fromLTRB(
            HiwiskiMetrics.space16,
            HiwiskiMetrics.space6,
            HiwiskiMetrics.space6,
            HiwiskiMetrics.space6,
          ),
          decoration: BoxDecoration(
            color: context.scheme.surfaceContainer,
            borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.recipeServings,
                  style: context.texts.bodyLarge?.copyWith(fontWeight: .w500),
                ),
              ),
              IconButton(
                icon: const Icon(HiwiskiSymbols.remove),
                tooltip: l.recipeServingsFewer,
                // Zero servings do not exist, and neither does a division by zero.
                onPressed: shown > 1
                    ? () => viewModel.setServings(shown - 1)
                    : null,
              ),
              SizedBox(
                width: HiwiskiMetrics.space28,
                child: Text(
                  '$shown',
                  textAlign: .center,
                  style: context.texts.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(HiwiskiSymbols.add),
                tooltip: l.recipeServingsMore,
                onPressed: () => viewModel.setServings(shown + 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space14),
        Text(l.recipeIngredients, style: context.tokens.text.sectionLabel),
        const SizedBox(height: HiwiskiMetrics.space4),
        if (scaled.isEmpty)
          Text(
            l.recipeNoIngredients,
            style: context.texts.bodyMedium?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          )
        else
          for (final item in scaled) _IngredientRow(ingredient: item),
      ],
    );

    // The preparation may link too: "Teig wie in #REC-4" is the same reference as
    // everywhere else.
    final preparation = page.content.trim().isEmpty
        ? null
        : Column(
            crossAxisAlignment: .stretch,
            children: [
              Text(
                l.recipePreparation,
                style: context.tokens.text.sectionLabel,
              ),
              const SizedBox(height: HiwiskiMetrics.space6),
              // Rendered like a page's text: images uploaded into it stand on
              // lines of their own and show as images or stacks — a plain
              // Markdown view left them out.
              TextBlocks(
                page: page,
                writable: writable,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                    .copyWith(
                      p: context.tokens.text.prose,
                      code: context.tokens.text.monoSmall,
                    ),
              ),
            ],
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns =
            constraints.maxWidth >= HiwiskiMetrics.recipeTwoColumnWidth;
        // **Wide, the image and the ingredients side by side, the preparation below
        // across the full width.** With the preparation in the column next to the
        // image, a long text ran on far below it and left a gap as tall as itself.
        return Column(
          crossAxisAlignment: .stretch,
          children: [
            if (twoColumns)
              Row(
                crossAxisAlignment: .start,
                spacing: HiwiskiMetrics.space28,
                children: [
                  Expanded(
                    child: RecipeImage(
                      page: page,
                      height: HiwiskiMetrics.recipeImageHeightWide,
                      editable: writable,
                    ),
                  ),
                  Expanded(child: ingredients),
                ],
              )
            else ...[
              RecipeImage(
                page: page,
                height: HiwiskiMetrics.recipeImageHeight,
                editable: writable,
              ),
              const SizedBox(height: HiwiskiMetrics.space20),
              ingredients,
            ],
            if (preparation != null) ...[
              SizedBox(
                height: twoColumns
                    ? HiwiskiMetrics.space28
                    : HiwiskiMetrics.space14,
              ),
              preparation,
            ],
          ],
        );
      },
    );
  }
}

/// "Ingredients as a two-column grid (amount 80 wide, bold / product), rows
/// separated."
class _IngredientRow extends StatelessWidget {
  const _IngredientRow({required this.ingredient});

  final Ingredient ingredient;

  static const _amountWidth = HiwiskiMetrics.labelColumnWidth;

  @override
  Widget build(BuildContext context) {
    final amount = [
      formatAmount(ingredient.amount),
      ingredient.unit ?? '',
    ].where((part) => part.isNotEmpty).join(' ');

    return Container(
      decoration: BoxDecoration(
        // The context is BoxBorder: abstract, a shorthand finds no constructor.
        // ignore: many_lints/prefer_shorthands_with_constructors
        border: Border(top: BorderSide(color: context.tokens.divider)),
      ),
      padding: const .symmetric(vertical: HiwiskiMetrics.space8),
      child: Row(
        crossAxisAlignment: .start,
        children: [
          SizedBox(
            width: _amountWidth,
            child: Text(
              amount,
              style: context.texts.bodyLarge?.copyWith(fontWeight: .w600),
            ),
          ),
          const SizedBox(width: HiwiskiMetrics.space8),
          Expanded(
            child: Text(ingredient.label, style: context.texts.bodyLarge),
          ),
          if (ingredient.uncertain)
            Icon(
              HiwiskiSymbols.help,
              size: HiwiskiMetrics.icon16,
              color: context.scheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }
}
