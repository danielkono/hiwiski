import 'package:flutter/material.dart';

import '../theme/hiwiski_metrics.dart';

/// **loading** — a 3 px high strip below the bar, the content stays in place.
///
/// It **always** takes up its height. An indicator that only appears while loading
/// pushes everything below it down, and whoever is just aiming misses. Never a
/// spinner in the middle.
class LoadingStrip extends StatelessWidget {
  const LoadingStrip({super.key, required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: HiwiskiMetrics.progressStripHeight,
      child: loading
          ? const LinearProgressIndicator(
              minHeight: HiwiskiMetrics.progressStripHeight,
            )
          : const SizedBox.shrink(),
    );
  }
}
