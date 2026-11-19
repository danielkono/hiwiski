import 'package:flutter/material.dart';

import '../api/hiwiski_failure.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_symbols.dart';
import '../theme/hiwiski_tokens.dart';
import 'failure_text.dart';

/// A line **above** the content, not instead of the content.
///
/// That applies to errors, to the offline notice and to the conflict banner: the
/// content stays visible and usable.
class NoticeBar extends StatelessWidget {
  const NoticeBar({
    super.key,
    required this.icon,
    required this.text,
    this.background,
    this.foreground,
    this.actionLabel,
    this.onAction,
  });

  /// **offline** — everything usable, one line in the content.
  factory NoticeBar.offline(BuildContext context, {String? text}) => .new(
    icon: HiwiskiSymbols.cloudOff,
    text: text ?? L.of(context).stateOffline,
  );

  /// **error** — line above the content.
  factory NoticeBar.error(
    BuildContext context, {
    required String text,
    VoidCallback? onRetry,
  }) => .new(
    icon: HiwiskiSymbols.errorOutline,
    text: text,
    background: Theme.of(context).colorScheme.errorContainer,
    foreground: Theme.of(context).colorScheme.onErrorContainer,
    actionLabel: onRetry == null ? null : L.of(context).actionRetry,
    onAction: onRetry,
  );

  /// **error** of whatever failed — a ViewModel's state, a call: its sentence
  /// (`failure_text.dart`), an unknown error as a server error.
  factory NoticeBar.failure(
    BuildContext context, {
    required Object error,
    VoidCallback? onRetry,
  }) => .error(
    context,
    text: failureText(context, HiwiskiFailure.from(error)),
    onRetry: onRetry,
  );

  /// **read-only** — visible notice **with a reason**.
  factory NoticeBar.readOnly(BuildContext context, {required String reason}) =>
      .new(icon: HiwiskiSymbols.lock, text: reason);

  final IconData icon;
  final String text;
  final Color? background;
  final Color? foreground;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final bg = background ?? scheme.surfaceContainer;
    final fg = foreground ?? scheme.onSurfaceVariant;

    return Container(
      width: .infinity,
      padding: const .symmetric(
        horizontal: HiwiskiMetrics.space16,
        vertical: HiwiskiMetrics.space10,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
      ),
      child: Row(
        children: [
          Icon(icon, size: HiwiskiMetrics.icon20, color: fg),
          const SizedBox(width: HiwiskiMetrics.space10),
          Expanded(
            child: Text(
              text,
              style: context.texts.bodySmall?.copyWith(color: fg),
            ),
          ),
          if ((actionLabel, onAction) case (final label?, final action?))
            TextButton(onPressed: action, child: Text(label)),
        ],
      ),
    );
  }
}
