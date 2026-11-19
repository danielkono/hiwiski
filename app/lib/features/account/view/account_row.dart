import 'package:flutter/material.dart';

import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';

/// A management row: icon, label, value, `chevron_right` — or `open_in_new` where the
/// tap leaves the app.
class AccountRow extends StatelessWidget {
  const AccountRow({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.value,
    this.leavesApp = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final String? value;

  /// The tap opens the browser, not a page of the app.
  final bool leavesApp;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = context.scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: HiwiskiMetrics.listRowHeight,
        ),
        child: Padding(
          padding: const .symmetric(
            horizontal: HiwiskiMetrics.space4,
            vertical: HiwiskiMetrics.space8,
          ),
          child: LayoutBuilder(
            builder: (context, row) => Row(
              children: [
                Icon(icon, size: HiwiskiMetrics.icon22, color: muted),
                const SizedBox(width: HiwiskiMetrics.space14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Text(label, style: context.texts.bodyLarge),
                      if (subtitle case final subtitle?)
                        Text(
                          subtitle,
                          style: context.texts.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                    ],
                  ),
                ),
                // Gives way to the label with large text instead of pushing past
                // the edge; a long server address wraps.
                //
                // Beside an expanded label a flexible value got half the row and used
                // only what it needed: the rest stayed empty at the right, and the
                // arrow of a row with a count stood in the middle of it, at another
                // place for every number of digits. Bounded instead, the label takes
                // the room and every arrow stands at the edge.
                if (value case final value?) ...[
                  const SizedBox(width: HiwiskiMetrics.space8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: row.maxWidth / 2),
                    child: Text(
                      value,
                      textAlign: .end,
                      style: context.texts.bodyMedium?.copyWith(color: muted),
                    ),
                  ),
                ],
                if (onTap != null) ...[
                  const SizedBox(width: HiwiskiMetrics.space6),
                  Icon(
                    leavesApp
                        ? HiwiskiSymbols.openInNew
                        : HiwiskiSymbols.chevronRight,
                    size: HiwiskiMetrics.icon20,
                    color: muted,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
