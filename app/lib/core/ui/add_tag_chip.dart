import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_tokens.dart';
import 'dashed_border.dart';
import 'tap_target.dart';

/// "+ Tag", dashed.
class AddTagChip extends StatelessWidget {
  const AddTagChip({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TapTarget(
    onTap: onTap,
    child: InkWell(
      onTap: onTap,
      borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
      child: DashedBorder(
        color: context.scheme.outline,
        radius: HiwiskiMetrics.radiusChip,
        width: HiwiskiMetrics.hairline,
        child: Padding(
          padding: const .symmetric(
            horizontal: HiwiskiMetrics.space10,
            vertical: HiwiskiMetrics.space6,
          ),
          child: Text(
            L.of(context).tagAdd,
            style: context.texts.labelMedium?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    ),
  );
}
