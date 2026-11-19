import 'package:flutter/material.dart';

import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_symbols.dart';
import '../theme/hiwiski_tokens.dart';
import 'color_tokens.dart';
import 'tap_target.dart';
import '../l10n/generated/app_localizations.dart';

/// The eight dots from the design.
class ColorPicker extends StatelessWidget {
  const ColorPicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // No gap of its own: the tap area around each dot keeps them apart.
    return Wrap(
      children: [
        for (final token in calendarColorTokens)
          TapTarget(
            onTap: () => onSelected(token),
            child: Semantics(
              label: colorLabel(L.of(context), token),
              selected: token == selected,
              button: true,
              child: InkWell(
                onTap: () => onSelected(token),
                customBorder: const CircleBorder(),
                child: Container(
                  width: HiwiskiMetrics.swatchSize,
                  height: HiwiskiMetrics.swatchSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.accent(accentOf(token)),
                    shape: .circle,
                  ),
                  child: token == selected
                      ? Icon(
                          HiwiskiSymbols.check,
                          size: HiwiskiMetrics.icon18,
                          color: tokens.onAccent,
                        )
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
