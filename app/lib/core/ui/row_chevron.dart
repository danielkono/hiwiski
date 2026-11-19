import 'package:flutter/material.dart';

import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_symbols.dart';
import '../theme/hiwiski_tokens.dart';

/// The arrow at the end of a row that opens a page of its own — always last, after a
/// count and after the row's actions, so the eye finds it at the same place in every
/// list.
class RowChevron extends StatelessWidget {
  const RowChevron({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .only(right: HiwiskiMetrics.space4),
    child: Icon(
      HiwiskiSymbols.chevronRight,
      size: HiwiskiMetrics.icon20,
      color: context.scheme.onSurfaceVariant,
    ),
  );
}
