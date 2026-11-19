import 'package:flutter/material.dart';

import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_tokens.dart';
import 'row_divider.dart';

/// The one card a managed list stands in — tags, calendars, categories: its rows
/// parted by lines, not each in a card of its own (see [RowDivider]).
class RowCard extends StatelessWidget {
  const RowCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    // A Material, not a coloured box: rows paint their ink on the nearest Material —
    // under a coloured box it stayed invisible.
    return Material(
      color: context.scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: context.scheme.outlineVariant),
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
      ),
      clipBehavior: .antiAlias,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) const RowDivider(),
            child,
          ],
        ],
      ),
    );
  }
}
