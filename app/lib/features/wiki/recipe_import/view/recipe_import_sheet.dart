import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/generated/export.dart' hide Mutation;
import '../../../../core/api/hiwiski_failure.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/failure_text.dart';
import '../../../../core/ui/loading_strip.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../../../core/ui/hiwiski_sheet.dart';
import '../../../../domain/wiki/wiki_models.dart';
import '../../../../domain/wiki/wiki_page.dart';
import '../../view/ingredient_editor.dart';
import '../../view/wiki_keys.dart';
import '../recipe_import_view_model.dart';

/// "Recipe from an address".
///
/// Enter the address → the server fetches and parses → **review screen**: title, image,
/// servings, ingredients in fields, uncertainly parsed ones **marked** and correctable,
/// target folder. Then "Import".
///
/// `recipeIngredient` is free text and never fully adds up; **so the review screen is
/// mandatory, not a convenience.**
Future<void> showRecipeImportSheet(
  BuildContext context, {
  String? targetId,
  required ValueChanged<String> onCreated,
}) {
  return showHiwiskiSheet<void>(
    context: context,
    title: L.of(context).recipeImport,
    builder: (context) => _ImportBody(targetId: targetId, onCreated: onCreated),
  );
}

class _ImportBody extends ConsumerStatefulWidget {
  const _ImportBody({this.targetId, required this.onCreated});

  /// The recipe branch the import was started from — the target until someone picks.
  final String? targetId;
  final ValueChanged<String> onCreated;

  @override
  ConsumerState<_ImportBody> createState() => _ImportBodyState();
}

class _ImportBodyState extends ConsumerState<_ImportBody> {
  final _url = TextEditingController();
  final _title = TextEditingController();
  final _servings = TextEditingController(text: '4');

  /// Description and steps as Markdown — shown in the review, so one sees what comes
  /// along before taking it, and can trim it.
  final _content = TextEditingController();

  /// The address being read; its answer fills the review.
  String? _fetched;
  List<Ingredient> _ingredients = const [];

  /// One key per ingredient row. A row reads its text once; without its own key, the
  /// rows after a removed one kept showing the old text over other data, and an edit
  /// there overwrote the wrong ingredient.
  List<int> _ingredientKeys = const [];
  var _nextIngredientKey = 0;
  late String? _targetId = widget.targetId;

  /// Until someone picks, a recipe collection is suggested — that is where recipes go.
  late bool _targetPicked = widget.targetId != null;
  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    _servings.dispose();
    _content.dispose();
    super.dispose();
  }

  void _fetch() {
    final url = _url.text.trim();
    if (url.isEmpty) return;
    // Asked again for the same address — after a failure, or a page that changed.
    if (url == _fetched) ref.invalidate(parsedRecipeViewModelProvider(url));
    setState(() => _fetched = url);
  }

  /// The review starts from what the server read; from then on it is the member's.
  void _fill(ParsedRecipe parsed) => setState(() {
    _title.text = parsed.title;
    _servings.text = '${parsed.servings ?? 4}';
    _content.text = parsed.content ?? '';
    _ingredients = [
      for (final line in parsed.ingredients)
        Ingredient(
          label: line.label,
          amount: line.amount?.toDouble(),
          unit: line.unit,
          uncertain: line.uncertain,
        ),
    ];
    _ingredientKeys = [
      for (int i = 0; i < _ingredients.length; i++) _nextIngredientKey++,
    ];
  });

  Future<void> _take() async {
    // A second tap while it ran created everything twice.
    if (ref.read(takeRecipeMutation).isPending) return;
    final parsed = switch (_fetched) {
      null => null,
      final url => ref.read(parsedRecipeViewModelProvider(url)).value,
    };
    final id = await takeRecipeMutation.run(
      ref,
      (tsx) => tsx
          .get(recipeImportViewModelProvider.notifier)
          .take(
            title: _title.text.trim(),
            parentId: _targetId,
            servings: int.tryParse(_servings.text) ?? 4,
            ingredients: _ingredients,
            content: _content.text,
            sourceUrl: parsed?.sourceUrl,
            durationMinutes: parsed?.durationMinutes,
          ),
    );

    widget.onCreated(id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final fetched = _fetched;
    final taking = ref.watch(takeRecipeMutation).isPending;
    final (fetching, error, parsed) = switch (fetched) {
      null => (false, null, null),
      final url =>
        ref
            .watch(parsedRecipeViewModelProvider(url))
            .when(
              skipLoadingOnReload: true,
              loading: () => (true, null, null),
              error: (error, _) => (
                false,
                failureText(context, HiwiskiFailure.from(error)),
                null,
              ),
              data: (parsed) => (false, null, parsed),
            ),
    };
    if (fetched != null) {
      ref.listen(parsedRecipeViewModelProvider(fetched), (_, next) {
        if (next.value case final parsed?) _fill(parsed);
      });
    }
    return ref
        .watch(recipeImportViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => const LoadingStrip(loading: true),
          error: (error, _) => NoticeBar.failure(context, error: error),
          data: (pages) {
            final l = L.of(context);
            if (!_targetPicked) {
              _targetId ??= pages
                  .where((page) => page.kind == kindRecipeFolder)
                  .firstOrNull
                  ?.id;
            }
            final uncertain = _ingredients
                .where((item) => item.uncertain)
                .length;

            return Column(
              crossAxisAlignment: .stretch,
              children: [
                Row(
                  spacing: HiwiskiMetrics.space8,
                  children: [
                    Expanded(
                      child: TextField(
                        key: WikiKeys.recipeUrl,
                        controller: _url,
                        keyboardType: .url,
                        decoration: InputDecoration(
                          labelText: l.recipeImportUrl,
                        ),
                      ),
                    ),
                    FilledButton(
                      onPressed: fetching ? null : _fetch,
                      child: Text(l.recipeImportFetch),
                    ),
                  ],
                ),
                if (error case final message?)
                  Padding(
                    padding: const .only(top: HiwiskiMetrics.space8),
                    child: Text(
                      message,
                      style: context.texts.bodySmall?.copyWith(
                        color: context.scheme.error,
                      ),
                    ),
                  ),
                if (parsed != null) ...[
                  const Divider(height: HiwiskiMetrics.space24),
                  TextField(
                    key: WikiKeys.recipeTitle,
                    controller: _title,
                    decoration: InputDecoration(labelText: l.wikiPageTitle),
                  ),
                  const SizedBox(height: HiwiskiMetrics.space12),
                  TextField(
                    key: WikiKeys.recipeServings,
                    controller: _servings,
                    keyboardType: .number,
                    decoration: InputDecoration(labelText: l.recipeServings),
                  ),
                  const SizedBox(height: HiwiskiMetrics.space16),
                  _TargetPicker(
                    selected: _targetId,
                    onChanged: (value) => setState(() {
                      _targetId = value;
                      _targetPicked = true;
                    }),
                  ),
                  const SizedBox(height: HiwiskiMetrics.space16),
                  Row(
                    children: [
                      Text(
                        l.recipeIngredients,
                        style: context.tokens.text.sectionLabel,
                      ),
                      const Spacer(),
                      if (uncertain > 0)
                        Text(
                          l.recipeImportUncertainCount(uncertain),
                          style: context.texts.bodySmall?.copyWith(
                            color: context.scheme.error,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: HiwiskiMetrics.space8),
                  for (var i = 0; i < _ingredients.length; i++)
                    IngredientEditor(
                      key: ValueKey(_ingredientKeys[i]),
                      ingredient: _ingredients[i],
                      onChanged: (value) =>
                          setState(() => _ingredients[i] = value),
                      onRemove: () => setState(() {
                        _ingredients.removeAt(i);
                        _ingredientKeys.removeAt(i);
                      }),
                    ),
                  const SizedBox(height: HiwiskiMetrics.space16),
                  Text(
                    l.recipePreparation,
                    style: context.tokens.text.sectionLabel,
                  ),
                  const SizedBox(height: HiwiskiMetrics.space8),
                  TextField(
                    key: WikiKeys.recipeContent,
                    controller: _content,
                    minLines: 4,
                    maxLines: 12,
                    style: context.tokens.text.monoSmall,
                  ),
                  SheetActions(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(l.actionCancel),
                      ),
                      FilledButton(
                        onPressed: taking ? null : _take,
                        child: Text(l.recipeTake),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        );
  }
}

class _TargetPicker extends ConsumerWidget {
  const _TargetPicker({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    // A recipe belongs in a folder, not in another recipe — collections first.
    final folders =
        ref.watch(recipeImportViewModelProvider).value ?? const <WikiPage>[];

    return DropdownButtonFormField<String?>(
      initialValue: selected,
      decoration: InputDecoration(
        labelText: l.recipeImportTarget,
        isDense: true,
      ),
      items: [
        DropdownMenuItem(value: null, child: Text(l.wikiMoveRoot)),
        for (final page in folders)
          DropdownMenuItem(value: page.id, child: Text(page.title)),
      ],
      onChanged: onChanged,
    );
  }
}
