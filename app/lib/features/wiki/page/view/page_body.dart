import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/archived_banner.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../../../domain/wiki/markdown_editing.dart';
import '../../../../domain/wiki/wiki_page.dart';
import '../page_view_model.dart';
import 'page_kind.dart';
import 'text/text_block.dart';

/// What a page shows while it is read: the archive mark, then what its kind shows
/// (`PageKindView`) — a collection's recipes, the recipe, or the rendered text. The page screen puts its header, comments and info bar
/// around it; a link's preview shows it as it is.
///
/// [preview]: ticking boxes and following links work, changing the page does not —
/// no new recipe, no image, no restore. A recipe in the grid opens its own preview.
class PageBody extends ConsumerWidget {
  const PageBody({
    super.key,
    required this.page,
    this.preview = false,
    this.onCreate,
    this.onImport,
    this.onRestore,
    this.sliver = false,
  });

  final WikiPage page;
  final bool preview;

  /// As slivers in the page's scroll view: a long text is rendered in blocks that are
  /// built as they come into view ([markdownChunks]).
  final bool sliver;

  /// Creates something below this page — for "New recipe" in an empty recipe collection.
  final void Function(String parentId, String kind)? onCreate;

  /// A recipe from an address into this page — offered in an empty recipe collection.
  final ValueChanged<String>? onImport;

  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(pageViewModelProvider(page.id))
      .when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (error, _) => NoticeBar.failure(context, error: error),
        data: (state) => state == null
            ? const SizedBox.shrink()
            : _PageBodyContent(
                onCreate: onCreate,
                onRestore: onRestore,
                onImport: onImport,
                sliver: sliver,
                preview: preview,
                page: page,
                state: state,
              ),
      );
}

class _PageBodyContent extends ConsumerWidget {
  const _PageBodyContent({
    required this.onCreate,
    required this.onRestore,
    required this.onImport,
    required this.sliver,
    required this.preview,
    required this.page,
    required this.state,
  });

  final void Function(String parentId, String kind)? onCreate;

  final VoidCallback? onRestore;
  final ValueChanged<String>? onImport;
  final bool sliver;
  final bool preview;
  final WikiPage page;
  final PageState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final kind = PageKindView.of(page);
    // An archived page is read-only — and so is everything it would
    // otherwise offer to change.
    final writable = state.mayChange && page.archivedAt == null;

    final head = <Widget>[
      if (page.archivedAt case final archivedAt?) ...[
        ArchivedBanner(
          archivedAt: archivedAt,
          archivedBy: state.archivedBy,
          onRestore: preview ? null : onRestore,
        ),
        const SizedBox(height: HiwiskiMetrics.space16),
      ],
      ...kind.head(
        context,
        page: page,
        state: state,
        actions: PageKindActions(
          preview: preview,
          writable: writable,
          onCreate: onCreate,
          onImport: onImport,
        ),
      ),
    ];

    final styleSheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: context.tokens.text.prose,
      code: context.tokens.text.monoSmall,
    );
    // A box's number counts across the blocks: the n-th box of the page, not of its
    // block.
    final chunks = markdownChunks(page.content);
    final offsets = <int>[];
    int offset = 0;
    for (final chunk in chunks) {
      offsets.add(offset);
      offset += taskCount(chunk);
    }
    final whole = kind.body(
      context,
      page: page,
      state: state,
      writable: writable && !preview,
    );
    final Widget? body = switch ((whole, page.content.trim().isEmpty)) {
      ([final single], _) => single,
      ([_, _, ...], _) => Column(crossAxisAlignment: .stretch, children: whole),
      ([], true) => Padding(
        padding: const .only(top: HiwiskiMetrics.space16),
        child: Text(
          l.stateEmptyTitle,
          style: context.texts.bodyMedium?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
      ),
      ([], false) => null,
    };

    if (sliver) {
      return SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: .stretch,
              children: [...head, ?body],
            ),
          ),
          if (body == null)
            SliverList.builder(
              itemCount: chunks.length,
              itemBuilder: (context, i) => TextBlock(
                page: page,
                chunk: chunks[i],
                first: i == 0,
                offset: offsets[i],
                writable: writable,
                styleSheet: styleSheet,
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        ...head,
        ?body,
        if (body == null)
          for (var i = 0; i < chunks.length; i++)
            TextBlock(
              page: page,
              chunk: chunks[i],
              first: i == 0,
              offset: offsets[i],
              writable: writable,
              styleSheet: styleSheet,
            ),
      ],
    );
  }
}
