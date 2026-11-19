import 'package:flutter/material.dart';

import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_tokens.dart';

/// The line under a row of a list, and between the rows of a [RowCard].
///
/// **A list has one of two forms.** What is ticked off or opened — a task, a shopping
/// entry, an event — is a flat row with this line under it. What is managed — tags,
/// calendars, categories — stands in one shared card, its rows parted by the same
/// line. A list used to choose for itself between a card per row, one card for all
/// and no line at all, and six lists looked like six apps.
class RowDivider extends StatelessWidget {
  const RowDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Divider(height: HiwiskiMetrics.hairline, color: context.tokens.divider);
}
