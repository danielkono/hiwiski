import 'package:flutter/material.dart';

import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_tokens.dart';

/// The states **every** screen must have.
///
/// "No screen counts as finished while one of them is missing. In an earlier version the empty
/// states were 'bare' — that is the state a new user sees first."
///
/// **empty** — icon, one sentence on what comes into being here, a button that creates
/// it. Never just a grey sentence.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    // Centered while it fits; with large text on a small screen it scrolls instead
    // of being cut off at the bottom.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.hasBoundedHeight ? constraints.maxHeight : 0,
            minWidth: constraints.maxWidth,
          ),
          child: Center(
            child: Padding(
              padding: const .all(HiwiskiMetrics.space32),
              child: Column(
                mainAxisSize: .min,
                children: [
                  Icon(
                    icon,
                    size: HiwiskiMetrics.icon48,
                    color: context.scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: HiwiskiMetrics.space16),
                  Text(
                    message,
                    textAlign: .center,
                    style: context.texts.bodyLarge,
                  ),
                  if ((actionLabel, onAction) case (
                    final label?,
                    final action?,
                  )) ...[
                    const SizedBox(height: HiwiskiMetrics.space20),
                    FilledButton(onPressed: action, child: Text(label)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
