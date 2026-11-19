import 'package:flutter/material.dart';

import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_symbols.dart';
import '../theme/hiwiski_tokens.dart';
import 'tap_target.dart';

/// A filter chip as in the design: outlined in `outl`; selected on `sec` with a check.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return TapTarget(
      onTap: onTap,
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
          child: Container(
            height: HiwiskiMetrics.chipHeight,
            padding: .only(
              left: selected ? HiwiskiMetrics.space8 : HiwiskiMetrics.space12,
              right: HiwiskiMetrics.space12,
            ),
            decoration: BoxDecoration(
              color: selected ? scheme.secondaryContainer : null,
              border: selected
                  ? null
                  : Border.fromBorderSide(BorderSide(color: scheme.outline)),
              borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
            ),
            child: Row(
              mainAxisSize: .min,
              children: [
                if (selected) ...[
                  Icon(
                    HiwiskiSymbols.check,
                    size: HiwiskiMetrics.icon18,
                    color: scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: HiwiskiMetrics.space4),
                ],
                Text(
                  label,
                  style: context.texts.labelLarge?.copyWith(
                    color: selected
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
