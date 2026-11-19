import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/loading_strip.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../../../core/ui/hiwiski_sheet.dart';
import '../../../../domain/wiki/wiki_models.dart';
import '../../../../domain/wiki/wiki_page.dart';
import '../../view/wiki_keys.dart';
import '../recipe_shopping_view_model.dart';

/// "Add to shopping list".
///
/// Sheet: "6 ingredients for 4 servings from *Pumpkin soup*", below it the existing
/// shopping lists as a radio group, then "New shopping list". Below that the
/// ingredient selection with the **scaled** amounts — **pantry staples are unchecked up front**.
Future<void> showRecipeShoppingSheet(
  BuildContext context, {
  required WikiPage page,
  required List<Ingredient> ingredients,
  required int servings,
}) {
  return showHiwiskiSheet<void>(
    context: context,
    title: L.of(context).recipeToShoppingList,
    builder: (context) => _RecipeShoppingBody(
      page: page,
      ingredients: ingredients,
      servings: servings,
    ),
  );
}

class _RecipeShoppingBody extends ConsumerStatefulWidget {
  const _RecipeShoppingBody({
    required this.page,
    required this.ingredients,
    required this.servings,
  });

  final WikiPage page;
  final List<Ingredient> ingredients;
  final int servings;

  @override
  ConsumerState<_RecipeShoppingBody> createState() =>
      _RecipeShoppingBodyState();
}

class _RecipeShoppingBodyState extends ConsumerState<_RecipeShoppingBody> {
  late final Set<int> _chosen = {
    for (var i = 0; i < widget.ingredients.length; i++)
      // Pantry staples are unchecked up front: everyone has salt.
      if (!widget.ingredients[i].staple) i,
  };

  final _newListName = TextEditingController();
  String? _listId;

  /// Whether the member chose — a list or a new one. Until then the first list is the
  /// suggestion; after that the choice is theirs. The suggestion used to be applied on
  /// every build, so "New shopping list" snapped straight back to the first list.
  bool _listChosen = false;

  @override
  void dispose() {
    _newListName.dispose();
    super.dispose();
  }

  Future<void> _take() async {
    // A second tap while it ran created everything twice.
    if (ref.read(addToShoppingMutation).isPending) return;
    final listId = await addToShoppingMutation.run(
      ref,
      (tsx) => tsx
          .get(recipeShoppingViewModelProvider.notifier)
          .add(
            [
              for (final index in _chosen.toList()..sort())
                widget.ingredients[index],
            ],
            listId: _listId,
            newName: _newListName.text,
          ),
    );
    if (listId == null) return;
    if (!mounted) return;
    // Then into the list: whoever transfers ingredients wants to see that they arrived.
    // Grab the router before closing — afterwards the sheet's context is gone.
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(TodoListRoute(listId: listId).location);
  }

  @override
  Widget build(BuildContext context) {
    final taking = ref.watch(addToShoppingMutation).isPending;
    return ref
        .watch(recipeShoppingViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => const LoadingStrip(loading: true),
          error: (error, _) => NoticeBar.failure(context, error: error),
          data: (lists) {
            final l = L.of(context);
            if (!_listChosen && _listId == null && lists.isNotEmpty) {
              _listId = lists.first.list.id;
            }

            return Column(
              crossAxisAlignment: .stretch,
              children: [
                Text(
                  l.recipeToShoppingListTitle(
                    widget.ingredients.length,
                    widget.servings,
                    widget.page.title,
                  ),
                  style: context.texts.bodyMedium,
                ),
                const SizedBox(height: HiwiskiMetrics.space16),
                RadioGroup<String?>(
                  groupValue: _listId,
                  onChanged: (value) => setState(() {
                    _listId = value;
                    _listChosen = true;
                  }),
                  child: Column(
                    crossAxisAlignment: .stretch,
                    children: [
                      for (final summary in lists)
                        RadioListTile<String?>(
                          contentPadding: EdgeInsets.zero,
                          value: summary.list.id,
                          title: Text(summary.list.name),
                          subtitle: Text(
                            L.of(context).widgetOpenCount(summary.open),
                          ),
                        ),
                      RadioListTile<String?>(
                        contentPadding: EdgeInsets.zero,
                        value: null,
                        title: Text(l.recipeNewList),
                      ),
                    ],
                  ),
                ),
                if (_listId == null)
                  TextField(
                    key: WikiKeys.newShoppingList,
                    controller: _newListName,
                    decoration: InputDecoration(labelText: l.recipeListName),
                  ),
                const Divider(height: HiwiskiMetrics.space24),
                for (var i = 0; i < widget.ingredients.length; i++)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _chosen.contains(i),
                    title: Text(widget.ingredients[i].label),
                    subtitle: switch (_amount(widget.ingredients[i])) {
                      null => null,
                      final amount => Text(amount),
                    },
                    secondary: widget.ingredients[i].staple
                        ? Chip(label: Text(l.recipeStaple))
                        : null,
                    onChanged: (checked) => setState(() {
                      if (checked ?? false) {
                        _chosen.add(i);
                      } else {
                        _chosen.remove(i);
                      }
                    }),
                  ),
                SheetActions(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l.actionCancel),
                    ),
                    FilledButton(
                      onPressed: _chosen.isEmpty || taking ? null : _take,
                      child: Text(l.recipeTake),
                    ),
                  ],
                ),
              ],
            );
          },
        );
  }

  static String? _amount(Ingredient item) {
    final text = [
      formatAmount(item.amount),
      item.unit ?? '',
    ].where((part) => part.isNotEmpty).join(' ');
    return text.isEmpty ? null : text;
  }
}
