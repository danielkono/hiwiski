import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/failure_text.dart';
import '../../../core/ui/loading_strip.dart';
import '../../../core/ui/notice_bar.dart';
import '../../../core/ui/sync_item_label.dart';
import '../../../core/ui/hiwiski_sheet.dart';
import '../../../domain/sync/sync_items.dart';
import '../sync_banner_view_model.dart';

/// What the server rejected — **as a visible list to copy from**.
///
/// "The client first tries to push its outbox; **whatever is rejected ends up in a
/// visible list to copy from instead of silently disappearing.**"
///
/// Without this list there is only the message and a "Try again" button — and if the
/// rejection is permanent, that fails again on every attempt. The message then stays
/// forever, and the user can do nothing about it. That is exactly what happened when
/// testing the fresh instance.
Future<void> showStuckSheet(BuildContext context) {
  return showHiwiskiSheet<void>(
    context: context,
    title: L.of(context).stuckTitle,
    builder: (context) => const _StuckBody(),
  );
}

class _StuckBody extends ConsumerWidget {
  const _StuckBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(stuckChangesViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => const LoadingStrip(loading: true),
          error: (error, _) => NoticeBar.failure(context, error: error),
          data: (stuck) => _StuckList(stuck: stuck),
        );
  }

  static Future<void> _retry(BuildContext context, WidgetRef ref) async {
    await ref.read(stuckChangesViewModelProvider.notifier).retry();
    if (context.mounted) Navigator.of(context).pop();
  }

  static Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final l = L.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.stuckDiscardConfirm),
        content: Text(l.stuckDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.stuckDiscardAll),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    await ref.read(stuckChangesViewModelProvider.notifier).discard();
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _StuckList extends ConsumerWidget {
  const _StuckList({required this.stuck});

  final List<OutboxChange> stuck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);

    if (stuck.isEmpty) {
      return Padding(
        padding: const .symmetric(vertical: HiwiskiMetrics.space20),
        child: Text(l.stuckEmpty, style: context.texts.bodyMedium),
      );
    }

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Text(
          l.stuckIntro,
          style: context.texts.bodySmall?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space16),
        for (final entry in stuck)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              HiwiskiSymbols.errorOutline,
              color: context.scheme.error,
            ),
            // The label given at creation: "Take out the trash", not a UUID.
            // Whoever is supposed to copy it needs to know what.
            title: Text(syncItemLabel(l, entry.entityType, entry.label)),
            subtitle: Text(switch (entry.errorCode) {
              null => entry.entityType,
              final code => failureTextForCode(context, code),
            }, style: context.texts.bodySmall),
          ),
        SheetActions(
          children: [
            TextButton(
              onPressed: () => _StuckBody._discard(context, ref),
              style: TextButton.styleFrom(
                foregroundColor: context.scheme.error,
              ),
              child: Text(l.stuckDiscardAll),
            ),
            FilledButton(
              onPressed: () => _StuckBody._retry(context, ref),
              child: Text(l.stuckRetryAll),
            ),
          ],
        ),
      ],
    );
  }
}
