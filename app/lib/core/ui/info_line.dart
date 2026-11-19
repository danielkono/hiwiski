import 'package:flutter/material.dart';

import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_tokens.dart';

/// A "label — value" row for the *Info* section.
class InfoLine extends StatelessWidget {
  const InfoLine({super.key, required this.label, required this.value});

  final String label;
  final String value;

  // Label small on top, the value below — as in the design ("Last edited" /
  // "Ben, today 07:12"). Side by side, the date slid to the edge in a narrow bar
  // and the label wrapped.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const .symmetric(vertical: HiwiskiMetrics.space4),
    child: Column(
      crossAxisAlignment: .start,
      spacing: HiwiskiMetrics.hairline,
      children: [
        Text(
          label,
          style: context.texts.bodySmall?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
        Text(value, style: context.texts.bodyMedium),
      ],
    ),
  );
}
