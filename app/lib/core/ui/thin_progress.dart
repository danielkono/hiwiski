import 'package:flutter/material.dart';

import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_tokens.dart';

/// The progress bar: 4 high, background `sf3`, fill `pri`.
class ThinProgress extends StatelessWidget {
  const ThinProgress({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: const .all(.circular(HiwiskiMetrics.radiusBar)),
    child: LinearProgressIndicator(
      value: value,
      minHeight: HiwiskiMetrics.barHeight,
      color: context.scheme.primary,
      backgroundColor: context.scheme.surfaceContainerHigh,
    ),
  );
}
