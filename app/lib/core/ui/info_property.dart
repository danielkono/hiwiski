import 'package:flutter/material.dart';

import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_symbols.dart';
import '../theme/hiwiski_tokens.dart';

/// A property in the first section: label small, the value below — tappable to
/// change, then with a pencil at the edge.
class InfoProperty extends StatelessWidget {
  const InfoProperty({
    super.key,
    required this.label,
    required this.value,
    this.dot,
    this.onTap,
  });

  final String label;
  final String value;

  /// The color dot — e.g. the calendar on an event.
  final Color? dot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = context.scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
      child: Padding(
        padding: const .symmetric(vertical: HiwiskiMetrics.space4),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: HiwiskiMetrics.hairline,
          children: [
            Text(
              label,
              style: context.texts.labelSmall?.copyWith(color: muted),
            ),
            Row(
              children: [
                if (dot != null) ...[
                  Container(
                    width: HiwiskiMetrics.dotSmall,
                    height: HiwiskiMetrics.dotSmall,
                    decoration: BoxDecoration(color: dot, shape: .circle),
                  ),
                  const SizedBox(width: HiwiskiMetrics.space8),
                ],
                Expanded(child: Text(value, style: context.texts.bodyLarge)),
                if (onTap != null)
                  Icon(
                    HiwiskiSymbols.edit,
                    size: HiwiskiMetrics.icon16,
                    color: muted,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
