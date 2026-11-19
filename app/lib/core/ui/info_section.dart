import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_tokens.dart';

/// A section in it: label, the rows below.
///
/// An empty section says "None" instead of disappearing — otherwise you could not tell
/// whether there is nothing or the app is still loading.
class InfoSection extends StatelessWidget {
  const InfoSection({
    super.key,
    required this.label,
    required this.children,
    this.emptyLabel,
    this.action,
  });

  final String label;
  final List<Widget> children;
  final String? emptyLabel;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Column(
      crossAxisAlignment: .start,
      children: [
        Text(label, style: context.tokens.text.sectionLabel),
        const SizedBox(height: HiwiskiMetrics.space6),
        if (children.isEmpty)
          Text(
            emptyLabel ?? l.linkNone,
            style: context.texts.bodyMedium?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          )
        else
          ...children,
        if (action case final action?) ...[
          const SizedBox(height: HiwiskiMetrics.space4),
          action,
        ],
      ],
    );
  }
}
