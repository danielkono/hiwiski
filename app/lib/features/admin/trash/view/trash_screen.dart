import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/generated/export.dart';
import '../../../../core/api/hiwiski_failure.dart';
import '../../../../core/common/wire.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/shell/breakpoints.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/failure_text.dart';
import '../../../../core/ui/page_header.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../../../core/ui/states.dart';
import '../trash_view_model.dart';
import 'restore_target_sheet.dart';

/// The trash.
///
/// **Forgotten in the design, mandatory here**. Deleted items from all
/// modules, sorted by time: type icon, title, mono number, "deleted by
/// Anna, the day before yesterday", "28 days left", a "Restore" button.
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = PageHeader(
      title: L.of(context).trashTitle,
      onBack: () => const AccountRoute().go(context),
    );
    return ref
        .watch(trashViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(
            header: header,
            error: error,
            onRetry: () => ref.read(trashViewModelProvider.notifier).retry(),
          ),
          data: (state) => _TrashPage(header: header, trash: state.trash),
        );
  }
}

class _TrashPage extends StatelessWidget {
  const _TrashPage({required this.header, required this.trash});

  final PageHeader header;
  final TrashList trash;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final padding = Breakpoint.of(context).pagePadding;
    return HiwiskiPage(
      header: header,
      body: trash.entries.isEmpty
          ? EmptyState(
              icon: HiwiskiSymbols.deleteOutline,
              message: l.trashEmpty,
            )
          : ListView(
              padding: padding,
              children: [
                for (final entry in trash.entries) _TrashRow(entry: entry),
                const SizedBox(height: HiwiskiMetrics.space16),
                Text(
                  // From the trash itself: the instance settings are for
                  // administrators, and everyone else was told the default.
                  l.trashNote(trash.retentionDays),
                  style: context.texts.bodySmall?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: HiwiskiMetrics.space32),
              ],
            ),
    );
  }
}

class _TrashRow extends ConsumerStatefulWidget {
  const _TrashRow({required this.entry});

  final TrashEntry entry;

  @override
  ConsumerState<_TrashRow> createState() => _TrashRowState();
}

class _TrashRowState extends ConsumerState<_TrashRow> {
  bool _busy = false;

  TrashEntry get entry => widget.entry;

  /// The type icon — for every type the server puts in the trash;
  /// only lists and tasks had one, and events, pages and tags looked alike.
  IconData get _icon => switch (entry.itemType) {
    EntityTypes.todoList => HiwiskiSymbols.checklist,
    EntityTypes.todo => HiwiskiSymbols.taskAlt,
    EntityTypes.calendar => HiwiskiSymbols.calendarMonth,
    EntityTypes.event => HiwiskiSymbols.event,
    EntityTypes.calendarSubscription ||
    EntityTypes.calendarFeed => HiwiskiSymbols.rssFeed,
    EntityTypes.wikiPage => HiwiskiSymbols.description,
    EntityTypes.tag => HiwiskiSymbols.sell,
    EntityTypes.board || EntityTypes.widget => HiwiskiSymbols.dashboard,
    _ => HiwiskiSymbols.deleteOutline,
  };

  /// Without a container and without a place to choose, there is nothing to offer.
  bool get _canRestore => entry.restorable || hasRestoreTarget(entry.itemType);

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = context.scheme;
    final who = ref
        .watch(trashViewModelProvider)
        .value
        ?.members[entry.deletedBy]
        ?.displayName;
    final when = DateFormat.yMMMd(Localizations.localeOf(context).toString())
        .format(entry.deletedAt);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_icon, color: scheme.onSurfaceVariant),
      title: Row(
        children: [
          Flexible(child: Text(entry.title, overflow: .ellipsis)),
          // The number gives way too, or large text pushes it past the edge.
          if (entry.entityKey case final entityKey?) ...[
            const SizedBox(width: HiwiskiMetrics.space8),
            Flexible(
              child: Text(
                entityKey,
                softWrap: false,
                overflow: .fade,
                style: context.tokens.text.entityKey,
              ),
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: .start,
        children: [
          Text(
            [
              if (who != null) l.trashDeletedBy(who, when) else when,
              l.trashRemaining(entry.remainingDays),
            ].join(' · '),
          ),
          // If its container is gone by now, restoring asks for a target.
          if (!entry.restorable)
            Text(
              l.trashNoContainer,
              style: context.texts.bodySmall?.copyWith(color: scheme.error),
            ),
        ],
      ),
      trailing: TextButton(
        onPressed: _busy || !_canRestore ? null : _restore,
        child: Text(l.trashRestore),
      ),
    );
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // The list may be older than the container's delete: then the server says so,
      // and the target is asked for all the same.
      bool gone = !entry.restorable;
      while (true) {
        String? target;
        if (gone) {
          if (!mounted) return;
          target = await showRestoreTargetSheet(
            context,
            itemType: entry.itemType,
          );
          if (target == null || !mounted) return;
        }
        try {
          // The restored item comes back to the device the normal way.
          await ref
              .read(trashViewModelProvider.notifier)
              .restore(entry, targetContainerId: target);
          return;
        } on HiwiskiFailure catch (failure) {
          if (gone ||
              failure.code != FailureCodes.trashContainerGone ||
              !hasRestoreTarget(entry.itemType)) {
            rethrow;
          }
          gone = true;
        }
      }
    } on HiwiskiFailure catch (failure) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(failureText(context, failure))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
