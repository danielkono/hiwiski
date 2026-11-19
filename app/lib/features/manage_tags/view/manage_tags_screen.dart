import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/row_card.dart';

import '../../../components/sharing/view/share_sheet.dart';
import '../../../components/tags/view/tag_widgets.dart';
import '../../../core/common/wire.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/shell/breakpoints.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/page_header.dart';
import '../../../core/ui/hiwiski_page.dart';
import '../../../core/ui/states.dart';
import '../../../core/ui/tag_chips.dart';
import '../../../domain/common/item_ref.dart';
import '../../../domain/tags/tag.dart';
import '../manage_tags_view_model.dart';

/// Tags: input "New tag" with "Create", the box below it.
///
/// **Split into my tags and those shared with me**, with the share on each of my own.
/// The note in the design — "Tags apply to the whole family ·
/// admin only" — is outdated.
class ManageTagsScreen extends ConsumerStatefulWidget {
  const ManageTagsScreen({super.key});

  @override
  ConsumerState<ManageTagsScreen> createState() => _ManageTagsScreenState();
}

class _ManageTagsScreenState extends ConsumerState<ManageTagsScreen> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    _name.clear();
    await createOwnTagMutation.run(
      ref,
      (tsx) => tsx.get(manageTagsViewModelProvider.notifier).create(name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final header = PageHeader(
      title: L.of(context).tagsTitle,
      onBack: () => const AccountRoute().go(context),
    );
    return ref
        .watch(manageTagsViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(header: header, error: error),
          data: _page,
        );
  }

  Widget _page(ManageTagsState state) {
    final l = L.of(context);
    final padding = Breakpoint.of(context).pagePadding;
    final mine = state.mine;
    final shared = state.shared;

    return HiwiskiPage(
      header: PageHeader(
        title: l.tagsTitle,
        detail: l.tagsCount(state.count),
        onBack: () => const AccountRoute().go(context),
      ),
      body: ListView(
        padding: padding.add(const .only(bottom: HiwiskiMetrics.space32)),
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: HiwiskiMetrics.listMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: .stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: HiwiskiMetrics.buttonHeight,
                          child: TextField(
                            controller: _name,
                            onSubmitted: (_) => _create(),
                            decoration: InputDecoration(
                              hintText: l.tagNew,
                              contentPadding: const .symmetric(
                                horizontal: HiwiskiMetrics.space16,
                              ),
                              border: const OutlineInputBorder(
                                borderRadius: .all(
                                  .circular(HiwiskiMetrics.radiusPill),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: HiwiskiMetrics.space8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(
                            0,
                            HiwiskiMetrics.buttonHeight,
                          ),
                        ),
                        icon: const Icon(
                          HiwiskiSymbols.add,
                          size: HiwiskiMetrics.icon20,
                        ),
                        label: Text(l.tagCreate),
                        onPressed: _create,
                      ),
                    ],
                  ),
                  const SizedBox(height: HiwiskiMetrics.space16),
                  if (state.count == 0)
                    EmptyState(icon: HiwiskiSymbols.sell, message: l.tagsEmpty),
                  if (mine.isNotEmpty) ...[
                    Text(l.tagsMine, style: context.tokens.text.sectionLabel),
                    const SizedBox(height: HiwiskiMetrics.space8),
                    _Box(
                      tags: mine,
                      own: true,
                      usage: state.usage,
                      shareable: state.shareable,
                    ),
                    const SizedBox(height: HiwiskiMetrics.space20),
                  ],
                  if (shared.isNotEmpty) ...[
                    Text(l.tagsShared, style: context.tokens.text.sectionLabel),
                    const SizedBox(height: HiwiskiMetrics.space8),
                    _Box(
                      tags: shared,
                      own: false,
                      usage: state.usage,
                      shareable: state.shareable,
                    ),
                    const SizedBox(height: HiwiskiMetrics.space20),
                  ],
                  Text(
                    l.tagsNote,
                    style: context.texts.bodySmall?.copyWith(
                      color: context.scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Box extends ConsumerWidget {
  const _Box({
    required this.tags,
    required this.own,
    required this.usage,
    required this.shareable,
  });

  final bool shareable;

  final List<Tag> tags;
  final bool own;

  /// How often each tag is used.
  final Map<String, int> usage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final muted = context.scheme.onSurfaceVariant;

    return RowCard(
      children: [
        for (var i = 0; i < tags.length; i++)
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: HiwiskiMetrics.listRowHeightTall,
            ),
            child: Padding(
              padding: const .fromLTRB(
                HiwiskiMetrics.space16,
                HiwiskiMetrics.space4,
                HiwiskiMetrics.space8,
                HiwiskiMetrics.space4,
              ),
              child: Row(
                children: [
                  TagChip(tag: tags[i]),
                  const SizedBox(width: HiwiskiMetrics.space14),
                  Expanded(
                    child: Text(
                      l.tagUsage(usage[tags[i].id] ?? 0),
                      style: context.texts.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                  if (own) ...[
                    if (shareable)
                      IconButton(
                        icon: Icon(
                          HiwiskiSymbols.share,
                          size: HiwiskiMetrics.icon20,
                          color: muted,
                        ),
                        tooltip: l.shareTitle,
                        onPressed: () => showShareSheet(
                          context,
                          item: ItemRef(EntityTypes.tag, tags[i].id),
                        ),
                      ),
                    IconButton(
                      icon: Icon(
                        HiwiskiSymbols.palette,
                        size: HiwiskiMetrics.icon20,
                        color: muted,
                      ),
                      tooltip: l.tagColor,
                      onPressed: () =>
                          showNewTagDialog(context, ref, editing: tags[i]),
                    ),
                    IconButton(
                      icon: Icon(
                        HiwiskiSymbols.edit,
                        size: HiwiskiMetrics.icon20,
                        color: muted,
                      ),
                      tooltip: l.tagEdit,
                      onPressed: () =>
                          showNewTagDialog(context, ref, editing: tags[i]),
                    ),
                    IconButton(
                      icon: Icon(
                        HiwiskiSymbols.delete,
                        size: HiwiskiMetrics.icon20,
                        color: muted,
                      ),
                      tooltip: l.actionDelete,
                      onPressed: () => ref
                          .read(manageTagsViewModelProvider.notifier)
                          .delete(tags[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
