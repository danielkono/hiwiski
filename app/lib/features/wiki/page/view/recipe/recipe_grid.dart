import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/l10n/generated/app_localizations.dart';
import '../../../../../core/theme/hiwiski_metrics.dart';
import '../../../../../core/theme/hiwiski_tokens.dart';
import '../../../../../domain/tags/tag.dart';
import '../../../../../domain/wiki/wiki_page.dart';
import '../../page_view_model.dart';
import 'recipe_image.dart';

/// Recipes as a **card grid** with a minimum width of 200: image 130 high, title, meta
/// ("35 min · vegetarian").
class RecipeGrid extends ConsumerWidget {
  const RecipeGrid({
    super.key,
    required this.pageId,
    required this.recipes,
    required this.onOpen,
  });

  /// The collection whose recipes these are.
  final String pageId;
  final List<WikiPage> recipes;
  final ValueChanged<WikiPage> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final tags =
        ref.watch(pageViewModelProvider(pageId)).value?.tags ?? const {};

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / HiwiskiMetrics.gridMinRecipe)
            .floor()
            .clamp(1, 6);
        final width =
            (constraints.maxWidth - (columns - 1) * HiwiskiMetrics.space14) /
            columns;
        return Wrap(
          spacing: HiwiskiMetrics.space14,
          runSpacing: HiwiskiMetrics.space14,
          children: [
            for (final recipe in recipes)
              SizedBox(
                width: width,
                child: Material(
                  color: context.scheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: context.scheme.outlineVariant),
                    borderRadius: const .all(
                      .circular(HiwiskiMetrics.radiusCard),
                    ),
                  ),
                  clipBehavior: .antiAlias,
                  child: InkWell(
                    onTap: () => onOpen(recipe),
                    child: Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        RecipeImage(
                          page: recipe,
                          height: HiwiskiMetrics.recipeImageHeightGrid,
                          radius: 0,
                          preview: true,
                        ),
                        Padding(
                          padding: const .symmetric(
                            horizontal: HiwiskiMetrics.space14,
                            vertical: HiwiskiMetrics.space12,
                          ),
                          child: Column(
                            crossAxisAlignment: .start,
                            spacing: HiwiskiMetrics.space4,
                            children: [
                              Text(
                                recipe.title,
                                style: context.texts.bodyLarge?.copyWith(
                                  fontWeight: .w600,
                                ),
                              ),
                              Text(
                                [
                                  if (recipe.durationMinutes
                                      case final minutes?)
                                    l.recipeMinutes(minutes),
                                  for (final id in tagIdsOf(recipe.tags))
                                    if (tags[id] case final tag?) tag.name,
                                ].join(' · '),
                                style: context.texts.bodySmall?.copyWith(
                                  color: context.scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
