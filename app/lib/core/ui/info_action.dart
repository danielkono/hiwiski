import 'package:flutter/material.dart';

import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_tokens.dart';
import 'tap_target.dart';

/// An action link below a section: "Assign", "Add", "+ Tag".
class InfoAction extends StatelessWidget {
  const InfoAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = context.scheme.primary;
    return TapTarget(
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const .symmetric(vertical: HiwiskiMetrics.space4),
          child: Row(
            mainAxisSize: .min,
            spacing: HiwiskiMetrics.space6,
            children: [
              Icon(icon, size: HiwiskiMetrics.icon18, color: color),
              // Wraps in a narrow bar instead of running past its edge.
              Flexible(
                child: Text(
                  label,
                  style: context.texts.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: .w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
