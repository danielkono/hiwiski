import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/common/wire.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/shell/breakpoints.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/archive_ui.dart';
import '../../../core/ui/list_kind_tile.dart';
import '../../../core/ui/page_header.dart';
import '../../../core/ui/hiwiski_page.dart';
import '../../../core/ui/states.dart';
import '../archive_view_model.dart';
import 'archive_keys.dart';

/// The archive — next to the trash, with the opposite promise: nothing here goes away
/// by itself.
class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = PageHeader(
      title: L.of(context).archiveTitle,
      onBack: () => const AccountRoute().go(context),
    );
    return ref
        .watch(archiveViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(header: header, error: error),
          data: (state) => _ArchivePage(header: header, state: state),
        );
  }
}

class _ArchivePage extends StatelessWidget {
  const _ArchivePage({required this.header, required this.state});

  final PageHeader header;
  final ArchiveState state;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final padding = Breakpoint.of(context).pagePadding;

    return HiwiskiPage(
      header: header,
      body: state.empty
          ? EmptyState(icon: HiwiskiSymbols.inventory2, message: l.archiveEmpty)
          : ListView(
              padding: padding,
              children: [
                if (state.pages.isNotEmpty) ...[
                  _GroupLabel(l.archiveGroupPages, state.pages.length),
                  for (final entry in state.pages) _PageEntry(entry: entry),
                ],
                if (state.recipes.isNotEmpty) ...[
                  _GroupLabel(l.archiveGroupRecipes, state.recipes.length),
                  for (final entry in state.recipes) _PageEntry(entry: entry),
                ],
                if (state.lists.isNotEmpty) ...[
                  _GroupLabel(l.archiveGroupLists, state.lists.length),
                  for (final entry in state.lists) _ListEntry(entry: entry),
                ],
                const SizedBox(height: HiwiskiMetrics.space16),
                Text(
                  l.archiveNote,
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

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label, this.count);

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .only(
      top: HiwiskiMetrics.space16,
      bottom: HiwiskiMetrics.space4,
    ),
    child: Text('$label · $count', style: context.tokens.text.sectionLabel),
  );
}

/// "archived by Anna · March 2026"
String _archivedLine(BuildContext context, DateTime? at, String? name) {
  final l = L.of(context);
  final when = at == null
      ? ''
      : DateFormat.yMMMM(Localizations.localeOf(context).toString())
            .format(at.toLocal());
  return name == null ? when : l.archiveArchivedBy(name, when);
}

class _PageEntry extends ConsumerWidget {
  const _PageEntry({required this.entry});

  final ArchivedPage entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final page = entry.page;
    final nested = entry.nested;
    return _Entry(
      key: ArchiveKeys.archive(page.id),
      icon: page.kind == PageKinds.recipe
          ? HiwiskiSymbols.restaurant
          : HiwiskiSymbols.description,
      title: page.title,
      entityKey: page.entityKey,
      lines: [
        _archivedLine(context, page.archivedAt, entry.archivedBy),
        if (nested > 0) l.archiveWithSubpagesCount(nested),
      ],
      onOpen: () => WikiRoute(pageId: page.id).push<void>(context),
      onRestore: entry.mayRestore
          ? () async {
              final withSubpages = nested == 0
                  ? false
                  : await askWithSubpages(
                      context,
                      subpages: nested,
                      restore: true,
                    );
              if (withSubpages == null || !context.mounted) return;
              await ref
                  .read(archiveViewModelProvider.notifier)
                  .restorePage(page, withSubpages: withSubpages);
            }
          : null,
    );
  }
}

class _ListEntry extends ConsumerWidget {
  const _ListEntry({required this.entry});

  final ArchivedList entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final summary = entry.summary;
    final list = summary.list;
    return _Entry(
      key: ArchiveKeys.archive(list.id),
      icon: listKindIcon(list.kind),
      title: list.name,
      lines: [
        _archivedLine(context, list.archivedAt, entry.archivedBy),
        l.archiveTaskCount(summary.open + summary.done),
      ],
      onOpen: () => TodoListRoute(listId: list.id).push<void>(context),
      onRestore: entry.mayRestore
          ? () => ref.read(archiveViewModelProvider.notifier).restoreList(entry)
          : null,
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    super.key,
    required this.icon,
    required this.title,
    required this.lines,
    required this.onOpen,
    this.entityKey,
    this.onRestore,
  });

  final IconData icon;
  final String title;
  final String? entityKey;
  final List<String> lines;
  final VoidCallback onOpen;

  /// `null` for whoever may only read: they see the entry, not the button.
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: context.scheme.onSurfaceVariant),
      title: Row(
        children: [
          Flexible(child: Text(title, overflow: .ellipsis)),
          if (entityKey case final entityKey?) ...[
            const SizedBox(width: HiwiskiMetrics.space8),
            Text(entityKey, style: context.tokens.text.entityKey),
          ],
        ],
      ),
      subtitle: Text(lines.where((line) => line.isNotEmpty).join(' · ')),
      // Opens the item exactly as it would open outside the archive.
      onTap: onOpen,
      trailing: onRestore == null
          ? null
          : TextButton(onPressed: onRestore, child: Text(l.archiveRestore)),
    );
  }
}
