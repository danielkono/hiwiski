import 'package:flutter/material.dart';

import '../../domain/tags/tag.dart';
import '../common/wire.dart';
import '../theme/hiwiski_accents.dart';
import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_symbols.dart';
import '../theme/hiwiski_tokens.dart';

// Tags as they look — chips, the filter bar, the colors. Passive: what they show
// comes from the screen's or the component's ViewModel.

/// A tag as a chip in its color: 13/500, radius 8.
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.tag,
    this.onRemove,
    this.dense = false,
  });

  final Tag tag;
  final VoidCallback? onRemove;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final pair = context.tokens.tags[tagTokenOf(tag.colorToken)]!;
    final child = Container(
      padding: .symmetric(
        horizontal: dense ? HiwiskiMetrics.space8 : HiwiskiMetrics.space10,
        vertical: dense ? HiwiskiMetrics.space4 : HiwiskiMetrics.space6,
      ),
      decoration: BoxDecoration(
        color: pair.background,
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
      ),
      // The cross as a symbol, not as "✕" in the text: Roboto has no such glyph, and
      // on the web, without a font from elsewhere, it showed as an empty box.
      child: Row(
        mainAxisSize: .min,
        spacing: HiwiskiMetrics.space4,
        children: [
          Text(
            tag.name,
            style:
                (dense ? context.texts.labelSmall : context.texts.labelMedium)
                    ?.copyWith(color: pair.foreground, fontWeight: .w500),
          ),
          if (onRemove != null)
            Icon(
              HiwiskiSymbols.close,
              size: HiwiskiMetrics.icon16,
              color: pair.foreground,
            ),
        ],
      ),
    );
    if (onRemove == null) return child;
    return InkWell(
      onTap: onRemove,
      borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
      child: child,
    );
  }
}

/// The theme color of a tag's wire color token.
TagToken tagTokenOf(String token) => switch (token) {
  ColorTokens.red => TagToken.red,
  ColorTokens.amber => TagToken.amber,
  ColorTokens.violet => TagToken.violet,
  ColorTokens.green => TagToken.green,
  ColorTokens.pink => TagToken.pink,
  _ => TagToken.blue,
};
