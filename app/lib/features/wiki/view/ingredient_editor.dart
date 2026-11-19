import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../domain/wiki/wiki_models.dart';

/// An ingredient row: amount, unit, product, and a cross to remove it.
///
/// Used by the import's review screen — **uncertainly parsed ones marked and
/// correctable** — and by editing a recipe, where the ingredients are typed by hand.
class IngredientEditor extends StatelessWidget {
  const IngredientEditor({
    super.key,
    required this.ingredient,
    required this.onChanged,
    required this.onRemove,
    this.handle,
  });

  /// At the start of the row: the grip that drags it to another place, while editing
  /// a recipe.
  final Widget? handle;

  final Ingredient ingredient;
  final ValueChanged<Ingredient> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final marked = ingredient.uncertain;

    return Container(
      margin: const .only(bottom: HiwiskiMetrics.space8),
      padding: const .all(HiwiskiMetrics.space8),
      decoration: BoxDecoration(
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
        border: .fromBorderSide(
          BorderSide(
            color: marked ? context.scheme.error : context.tokens.divider,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Row(
            children: [
              ?handle,
              SizedBox(
                width: HiwiskiMetrics.shortFieldWidth,
                child: TextFormField(
                  initialValue: formatAmount(ingredient.amount),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: .none,
                  ),
                  // Built anew rather than `copyWith`: an emptied field has to clear the
                  // amount, and `copyWith` would keep the old one.
                  onChanged: (value) => onChanged(
                    _with(
                      ingredient,
                      amount: double.tryParse(value.replaceAll(',', '.')),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: HiwiskiMetrics.shortFieldWidth,
                child: TextFormField(
                  initialValue: ingredient.unit ?? '',
                  decoration: const InputDecoration(
                    isDense: true,
                    border: .none,
                  ),
                  onChanged: (value) => onChanged(
                    _with(
                      ingredient,
                      unit: value.trim().isEmpty ? null : value.trim(),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: TextFormField(
                  initialValue: ingredient.label,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: .none,
                  ),
                  onChanged: (value) => onChanged(
                    ingredient.copyWith(label: value, uncertain: false),
                  ),
                ),
              ),
              IconButton(
                iconSize: HiwiskiMetrics.icon18,
                icon: const Icon(HiwiskiSymbols.close),
                tooltip: L.of(context).recipeIngredientRemove,
                onPressed: onRemove,
              ),
            ],
          ),
          if (marked)
            Padding(
              padding: const .only(top: HiwiskiMetrics.space4),
              child: Text(
                l.recipeImportUncertain,
                style: context.texts.bodySmall?.copyWith(
                  color: context.scheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The ingredient with a new amount or unit — `null` included. Whoever touches a row
/// has reviewed it, so it is no longer uncertain.
Ingredient _with(
  Ingredient base, {
  Object? amount = _keep,
  Object? unit = _keep,
}) => .new(
  label: base.label,
  amount: identical(amount, _keep) ? base.amount : amount as double?,
  unit: identical(unit, _keep) ? base.unit : unit as String?,
  productId: base.productId,
  staple: base.staple,
  optional: base.optional,
);

const _keep = Object();
