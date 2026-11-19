import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/common/wire.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/hiwiski_sheet.dart';
import '../../../core/ui/loading_strip.dart';
import '../../../core/ui/notice_bar.dart';
import '../../../domain/sync/sync_items.dart';
import '../sync_banner_view_model.dart';

/// **What a backup restore left behind on this device**.
///
/// The server was restored to an older state, and this device had seen more: a task
/// created since, a list renamed since. Brought back, it goes to the server like any
/// change made here — after a lost server, that is the week between the backup and
/// the loss, from the phones.
Future<void> showLeftBehindSheet(BuildContext context) =>
    showHiwiskiSheet<void>(
      context: context,
      title: L.of(context).leftBehindTitle,
      builder: (context) => const _LeftBehindBody(),
    );

class _LeftBehindBody extends ConsumerWidget {
  const _LeftBehindBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(leftBehindViewModelProvider)
      .when(
        skipLoadingOnReload: true,
        loading: () => const LoadingStrip(loading: true),
        error: (error, _) => NoticeBar.failure(context, error: error),
        data: (items) => _LeftBehindList(items: items),
      );
}

class _LeftBehindList extends ConsumerWidget {
  const _LeftBehindList({required this.items});

  final List<LeftBehindItem> items;

  static IconData _icon(String type) => switch (type) {
    EntityTypes.todoList => HiwiskiSymbols.checklist,
    EntityTypes.todo => HiwiskiSymbols.taskAlt,
    EntityTypes.calendar => HiwiskiSymbols.calendarMonth,
    EntityTypes.event => HiwiskiSymbols.event,
    EntityTypes.calendarSubscription ||
    EntityTypes.calendarFeed => HiwiskiSymbols.rssFeed,
    EntityTypes.wikiPage => HiwiskiSymbols.description,
    EntityTypes.tag => HiwiskiSymbols.sell,
    EntityTypes.board || EntityTypes.widget => HiwiskiSymbols.dashboard,
    _ => HiwiskiSymbols.backup,
  };

  Future<void> _restoreAll(BuildContext context, WidgetRef ref) async {
    await ref.read(leftBehindViewModelProvider.notifier).restore();
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _discardAll(BuildContext context, WidgetRef ref) async {
    final l = L.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.leftBehindDiscardConfirm),
        content: Text(l.leftBehindDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.leftBehindDiscardAll),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) return;
    await ref.read(leftBehindViewModelProvider.notifier).discard();
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    if (items.isEmpty) {
      return Padding(
        padding: const .symmetric(vertical: HiwiskiMetrics.space20),
        child: Text(l.leftBehindEmpty, style: context.texts.bodyMedium),
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Text(
          l.leftBehindIntro,
          style: context.texts.bodySmall?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space16),
        for (final item in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_icon(item.entityType)),
            title: Text(item.label.isEmpty ? item.entityType : item.label),
            subtitle: item.deleted
                ? Text(l.leftBehindDeleted, style: context.texts.bodySmall)
                : null,
            trailing: TextButton(
              onPressed: () => unawaited(
                ref.read(leftBehindViewModelProvider.notifier).restore(item),
              ),
              child: Text(l.leftBehindRestoreOne),
            ),
          ),
        SheetActions(
          children: [
            TextButton(
              onPressed: () => unawaited(_discardAll(context, ref)),
              style: TextButton.styleFrom(
                foregroundColor: context.scheme.error,
              ),
              child: Text(l.leftBehindDiscardAll),
            ),
            FilledButton(
              onPressed: () => unawaited(_restoreAll(context, ref)),
              child: Text(l.leftBehindRestoreAll),
            ),
          ],
        ),
      ],
    );
  }
}
