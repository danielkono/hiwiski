import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../../core/common/wire.dart';
import '../../../../../core/l10n/generated/app_localizations.dart';
import '../../../../../core/shell/breakpoints.dart';
import '../../../../../core/theme/hiwiski_metrics.dart';
import '../../../../../core/theme/hiwiski_symbols.dart';
import '../../../../../core/theme/hiwiski_tokens.dart';
import '../../../../../core/ui/field_pair.dart';
import '../../../../../core/ui/info_property.dart';
import '../../../../../domain/common/change.dart';
import '../../../../../domain/wiki/wiki_models.dart';
import '../../../../../domain/wiki/wiki_page.dart';
import '../../../view/ingredient_editor.dart';
import '../../../view/wiki_keys.dart';
import '../../page_view_model.dart';
import '../page_kind.dart';
import 'recipe_shopping_button.dart';
import 'recipe_view.dart';

/// A recipe: servings, time and source, the ingredients scaled to the servings, the
/// preparation as Markdown — and "Add to shopping list" docked below it.
class RecipeKindView extends PageKindView {
  const RecipeKindView();

  @override
  String get code => PageKinds.recipe;

  /// Only inside a recipe collection: that is where recipes are kept.
  @override
  String? offeredAs(L l, WikiNode? parent) =>
      parent?.isRecipeBranch ?? false ? l.wikiNewRecipe : null;

  @override
  IconData icon(WikiNode? parent) => HiwiskiSymbols.restaurant;

  @override
  IconData treeIcon(WikiNode node) => HiwiskiSymbols.restaurant;

  @override
  List<Widget> body(
    BuildContext context, {
    required WikiPage page,
    required PageState state,
    required bool writable,
  }) => [RecipeView(page: page, writable: writable)];

  @override
  List<Widget> properties(
    BuildContext context, {
    required WikiPage page,
    required String location,
    required VoidCallback? onMove,
  }) {
    final l = L.of(context);
    return [
      InfoProperty(label: l.recipeServings, value: '${page.servings ?? 4}'),
      if (page.durationMinutes case final minutes?)
        InfoProperty(label: l.recipeTime, value: l.recipeMinutes(minutes)),
      if (page.sourceUrl case final source? when source.isNotEmpty)
        InfoProperty(
          label: l.recipeSource,
          value: Uri.tryParse(source)?.host ?? source,
        ),
      InfoProperty(label: l.recipeFolder, value: location, onTap: onMove),
    ];
  }

  @override
  List<Widget> dock(BuildContext context, {required WikiPage page}) {
    final compact = Breakpoint.of(context).isCompact;
    return [
      Container(
        decoration: compact
            ? BoxDecoration(
                color: context.scheme.surfaceContainer,
                // The context is BoxBorder: abstract, a shorthand finds no constructor.
                // ignore: many_lints/prefer_shorthands_with_constructors
                border: Border(
                  top: BorderSide(color: context.scheme.outlineVariant),
                ),
              )
            : null,
        padding: compact
            ? const EdgeInsets.symmetric(
                horizontal: HiwiskiMetrics.space16,
                vertical: HiwiskiMetrics.space10,
              )
            : const EdgeInsets.fromLTRB(
                HiwiskiMetrics.space20,
                HiwiskiMetrics.space14,
                HiwiskiMetrics.space20,
                HiwiskiMetrics.space20,
              ),
        child: SafeArea(top: false, child: RecipeShoppingButton(page: page)),
      ),
    ];
  }

  @override
  PageKindDraft draft(WikiPage page) => RecipeDraft(page);
}

/// Editing a recipe: servings, time and source, the ingredients row by row — then the
/// preparation as Markdown below, like every page. Without these fields a recipe of
/// one's own stayed an empty shell — only an import filled them.
class RecipeDraft extends PageKindDraft {
  RecipeDraft(WikiPage page)
    : _servings = TextEditingController(text: '${page.servings ?? 4}'),
      _duration = TextEditingController(
        text: page.durationMinutes?.toString() ?? '',
      ),
      _source = TextEditingController(text: page.sourceUrl ?? ''),
      _ingredients = Ingredient.decode(page.ingredients).toList() {
    _ingredientKeys = [
      for (var i = 0; i < _ingredients.length; i++) _nextIngredientKey++,
    ];
  }

  final TextEditingController _servings;
  final TextEditingController _duration;
  final TextEditingController _source;
  final List<Ingredient> _ingredients;

  /// One key per ingredient row, so a row keeps its focus while others come and go.
  late final List<int> _ingredientKeys;
  int _nextIngredientKey = 0;

  @override
  void dispose() {
    _servings.dispose();
    _duration.dispose();
    _source.dispose();
    super.dispose();
  }

  @override
  List<Widget> fields(BuildContext context) {
    final l = L.of(context);
    return [
      FieldPair(
        children: [
          TextField(
            key: WikiKeys.recipeServings,
            controller: _servings,
            keyboardType: .number,
            decoration: InputDecoration(labelText: l.recipeServings),
          ),
          TextField(
            key: WikiKeys.recipeDuration,
            controller: _duration,
            keyboardType: .number,
            decoration: InputDecoration(
              labelText: l.recipeDuration,
              suffixText: l.unitMinutesSuffix,
            ),
          ),
        ],
      ),
      const SizedBox(height: HiwiskiMetrics.space12),
      TextField(
        key: WikiKeys.recipeSource,
        controller: _source,
        keyboardType: .url,
        decoration: InputDecoration(labelText: l.recipeSource),
      ),
      const SizedBox(height: HiwiskiMetrics.space20),
      Text(l.recipeIngredients, style: context.tokens.text.sectionLabel),
      const SizedBox(height: HiwiskiMetrics.space8),
      // Rows move by their grip — at once, with a finger too: the fields take every
      // other touch, and a long press would select their text instead.
      ReorderableListView(
        key: WikiKeys.recipeIngredientList,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderItem: _move,
        children: [
          for (var i = 0; i < _ingredients.length; i++)
            IngredientEditor(
              key: ValueKey(_ingredientKeys[i]),
              ingredient: _ingredients[i],
              handle: ReorderableDragStartListener(
                index: i,
                child: Padding(
                  padding: const .only(right: HiwiskiMetrics.space4),
                  child: Icon(
                    HiwiskiSymbols.dragIndicator,
                    key: WikiKeys.recipeIngredientHandle(i),
                    size: HiwiskiMetrics.icon20,
                    color: context.scheme.onSurfaceVariant,
                  ),
                ),
              ),
              onChanged: (value) {
                _ingredients[i] = value;
                notifyListeners();
              },
              onRemove: () {
                _ingredients.removeAt(i);
                _ingredientKeys.removeAt(i);
                notifyListeners();
              },
            ),
        ],
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(HiwiskiSymbols.add),
          label: Text(l.recipeAddIngredient),
          onPressed: () {
            _ingredients.add(const Ingredient(label: ''));
            _ingredientKeys.add(_nextIngredientKey++);
            notifyListeners();
          },
        ),
      ),
      const SizedBox(height: HiwiskiMetrics.space20),
      Text(l.recipePreparation, style: context.tokens.text.sectionLabel),
      const SizedBox(height: HiwiskiMetrics.space8),
    ];
  }

  /// An ingredient dragged from [from] to [to], its key with it so the row keeps
  /// what is typed in it.
  void _move(int from, int to) {
    if (from == to) return;
    _ingredients.insert(to, _ingredients.removeAt(from));
    _ingredientKeys.insert(to, _ingredientKeys.removeAt(from));
    notifyListeners();
  }

  @override
  Future<void> save(
    PageViewModel viewModel,
    WikiPage base, {
    required String? title,
    required String? content,
  }) {
    // Only what changed goes out — a field nobody touched must not overwrite what
    // someone else changed meanwhile.
    final servings = int.tryParse(_servings.text.trim());
    final duration = int.tryParse(_duration.text.trim());
    final source = _source.text.trim().isEmpty ? null : _source.text.trim();
    final ingredients = [
      for (final item in _ingredients)
        if (item.label.trim().isNotEmpty) item,
    ];
    String encoded(List<Ingredient> items) =>
        jsonEncode([for (final item in items) item.toJson()]);
    final ingredientsChanged =
        encoded(ingredients) != encoded(Ingredient.decode(base.ingredients));
    return viewModel.edit(
      base,
      title: title,
      content: content,
      properties: recipeChanges(
        servings: servings != null && servings > 0 && servings != base.servings
            ? Change(servings)
            : null,
        durationMinutes: duration != base.durationMinutes
            ? Change(duration)
            : null,
        sourceUrl: source != base.sourceUrl ? Change(source) : null,
        ingredients: ingredientsChanged ? ingredients : null,
      ),
    );
  }
}
