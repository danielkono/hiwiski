import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/common/wire.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/ui/history_field_label.dart';
import '../../../core/ui/notice_bar.dart';
import '../../../core/ui/scene_frame.dart';
import '../../../core/ui/hiwiski_sheet.dart';
import '../../../core/ui/ui_keys.dart';
import '../../../domain/links/link_text.dart';
import '../../../domain/sync/sync_items.dart';
import '../sync_banner_view_model.dart';
import 'conflict_sheet.dart';
import 'left_behind_sheet.dart';
import 'stuck_sheet.dart';

/// The sync states, above the content.
///
/// **Offline and conflict belong on every screen**. In an earlier version there
/// was a banner in the lists, and on two of four screens not even that — a conflict
/// nobody sees is data loss.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key, this.padding});

  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(syncBannerViewModelProvider)
      .when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (error, _) => Padding(
          padding: padding ?? .zero,
          child: NoticeBar.failure(context, error: error),
        ),
        data: (state) => _Banner(padding: padding, state: state),
      );
}

class _Banner extends ConsumerWidget {
  const _Banner({required this.padding, required this.state});

  final EdgeInsets? padding;
  final SyncBannerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final status = state.status;
    final conflicts = state.conflicts;

    final notices = <Widget>[
      // The demo keeps nothing, and says so on every page. A scene on
      // the website does not: the page around it says so once.
      if (state.demo && !SceneFrame.isScene(context))
        NoticeBar(icon: HiwiskiSymbols.science, text: l.demoBanner),
      // A tab left open across an update: the old app against the new server.
      if (state.webUpdate)
        NoticeBar(
          key: CoreKeys.webUpdate,
          icon: HiwiskiSymbols.refresh,
          text: l.webUpdateAvailable,
          actionLabel: l.webUpdateReload,
          onAction: () =>
              ref.read(syncBannerViewModelProvider.notifier).reload(),
        ),
      // Everything stays usable, one line says so. The app locks nothing. In the
      // browser with a catch: there the queue does not survive the tab.
      if (!status.online)
        NoticeBar.offline(context, text: kIsWeb ? l.stateOfflineWeb : null),
      // "Plan vacation and 3 more changes could not be applied."
      if (status.stuck > 0)
        NoticeBar(
          icon: HiwiskiSymbols.errorOutline,
          text: l.syncStuck(status.stuck),
          background: Theme.of(context).colorScheme.errorContainer,
          foreground: Theme.of(context).colorScheme.onErrorContainer,
          // **Look instead of retrying blindly.** If the rejection is permanent,
          // "Try again" fails again on every attempt — and the message stays forever.
          // The list shows *what* is stuck and *why*, and lets you copy it down.
          actionLabel: l.stuckShow,
          onAction: () => showStuckSheet(context),
        ),
      // After a restore: what this device had and the server lost. Said once, as one
      // bar; the list opens on demand.
      if (state.leftBehind > 0)
        NoticeBar(
          icon: HiwiskiSymbols.backup,
          text: l.leftBehindNotice(state.leftBehind),
          background: Theme.of(context).colorScheme.secondaryContainer,
          foreground: Theme.of(context).colorScheme.onSecondaryContainer,
          actionLabel: l.leftBehindShow,
          onAction: () => showLeftBehindSheet(context),
        ),
      // One conflict is one bar. From the second on, a bar each pushed the content
      // off the screen — then one bar counts them and the list opens on demand.
      if (conflicts.length == 1)
        _ConflictNotice(conflict: conflicts.single)
      else if (conflicts.length > 1)
        NoticeBar(
          icon: HiwiskiSymbols.merge,
          text: l.stateConflictCount(conflicts.length),
          background: Theme.of(context).colorScheme.tertiaryContainer,
          foreground: Theme.of(context).colorScheme.onTertiaryContainer,
          actionLabel: l.stateConflictShow,
          onAction: () => _showConflictList(context),
        ),
    ];

    if (notices.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding:
          padding ??
          const EdgeInsets.only(
            left: HiwiskiMetrics.space16,
            right: HiwiskiMetrics.space16,
            bottom: HiwiskiMetrics.space12,
          ),
      child: Column(
        children: [
          for (final notice in notices) ...[
            notice,
            const SizedBox(height: HiwiskiMetrics.space8),
          ],
        ]..removeLast(),
      ),
    );
  }
}

/// A conflict as a banner.
///
/// The wiki text is the special case: the losing version sits in the
/// history as a conflict revision, and there it can be read and restored. An "apply
/// anyway" without looking would mean blindly overwriting half an hour of the other
/// person's work.
class _ConflictNotice extends ConsumerWidget {
  const _ConflictNotice({required this.conflict});

  final SyncConflict conflict;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    // One line in the banner; the decision happens in the sheet, where all three
    // versions can be read side by side.
    return NoticeBar(
      icon: HiwiskiSymbols.merge,
      text: _conflictText(context, conflict),
      background: Theme.of(context).colorScheme.tertiaryContainer,
      foreground: Theme.of(context).colorScheme.onTertiaryContainer,
      actionLabel: l.stateConflictShow,
      onAction: () => showConflictSheet(context, conflict),
    );
  }
}

/// What a conflict is about, in one line.
String _conflictText(BuildContext context, SyncConflict conflict) {
  final l = L.of(context);
  return conflict.entityType == EntityTypes.wikiPage &&
          conflict.field == WireFields.content
      ? l.stateConflictWiki(
          DateFormat.Hm(Localizations.localeOf(context).toString())
              .format(conflict.detectedAt.toLocal()),
        )
      : l.stateConflictField(historyFieldLabel(l, conflict.field));
}

Future<void> _showConflictList(BuildContext context) => showHiwiskiSheet<void>(
  context: context,
  title: L.of(context).conflictListTitle,
  builder: (context) => const _ConflictList(),
);

/// All open conflicts, each one opening its own sheet. A resolved one drops out; when
/// none is left, the list closes itself.
class _ConflictList extends ConsumerWidget {
  const _ConflictList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(syncBannerViewModelProvider.select((s) => s.value?.conflicts), (
      previous,
      next,
    ) {
      if ((next?.isEmpty ?? false) && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
    final state = ref.watch(syncBannerViewModelProvider).value;
    if (state == null) return const SizedBox.shrink();
    final conflicts = state.conflicts;
    final index = state.index;

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        for (final conflict in conflicts)
          ListTile(
            key: CoreKeys.conflict(conflict.id),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(HiwiskiSymbols.merge),
            // The item, where it is known — "Title was changed" alone does not say
            // which of twelve tasks.
            title: Text(
              index
                      .resolve(
                        UriReference(conflict.entityType, conflict.entityId),
                      )
                      ?.title ??
                  historyFieldLabel(L.of(context), conflict.field),
              maxLines: 1,
              overflow: .ellipsis,
            ),
            subtitle: Text(_conflictText(context, conflict)),
            trailing: const Icon(HiwiskiSymbols.chevronRight),
            onTap: () => showConflictSheet(context, conflict),
          ),
      ],
    );
  }
}
