import 'package:flutter/material.dart';

import '../../domain/tags/tag.dart';
import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_symbols.dart';
import '../theme/hiwiski_tokens.dart';
import 'tag_chips.dart';
import 'tap_target.dart';
import 'color_tokens.dart';
import '../l10n/generated/app_localizations.dart';

/// The six tag colors as dots.
class TagColorPicker extends StatelessWidget {
  const TagColorPicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  // No gap of its own: the tap area around each dot keeps them apart.
  Widget build(BuildContext context) => Wrap(
    children: [
      for (final token in tagColorTokens)
        TapTarget(
          onTap: () => onSelected(token),
          child: Semantics(
            label: colorLabel(L.of(context), token),
            selected: token == selected,
            button: true,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onSelected(token),
              child: Container(
                width: HiwiskiMetrics.swatchSize,
                height: HiwiskiMetrics.swatchSize,
                decoration: BoxDecoration(
                  shape: .circle,
                  color: context.tokens.tags[tagTokenOf(token)]!.background,
                  border: .fromBorderSide(
                    BorderSide(
                      color: token == selected
                          ? context.scheme.onSurface
                          : context.scheme.outlineVariant,
                      width: token == selected
                          ? HiwiskiMetrics.strokeBold
                          : HiwiskiMetrics.hairline,
                    ),
                  ),
                ),
                child: token == selected
                    ? Icon(
                        HiwiskiSymbols.check,
                        size: HiwiskiMetrics.icon18,
                        color:
                            context.tokens.tags[tagTokenOf(token)]!.foreground,
                      )
                    : null,
              ),
            ),
          ),
        ),
    ],
  );
}
