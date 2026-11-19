import 'package:flutter/material.dart';

import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_tokens.dart';

/// "2/5" — over the pile's front image and below the large view.
class ImageCounter extends StatelessWidget {
  const ImageCounter({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.scheme.inverseSurface.withValues(alpha: 0.7),
      borderRadius: const .all(.circular(HiwiskiMetrics.radiusPill)),
    ),
    child: Padding(
      padding: const .symmetric(
        horizontal: HiwiskiMetrics.space8,
        vertical: HiwiskiMetrics.space2,
      ),
      child: Text(
        text,
        style: context.texts.labelSmall?.copyWith(
          color: context.scheme.onInverseSurface,
        ),
      ),
    ),
  );
}
