import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/common/wire.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/item_navigation.dart';
import '../../../core/routing/routes.dart';
import '../../../core/shell/breakpoints.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/archive_ui.dart';
import '../../../core/ui/failure_text.dart';
import '../../../core/ui/filter_pill.dart';
import '../../../core/ui/notice_bar.dart';
import '../../../core/ui/page_header.dart';
import '../../../core/ui/hiwiski_page.dart';
import '../../../core/ui/states.dart';
import '../../../core/ui/tag_filter_bar.dart';
import '../../../domain/search/search_models.dart';
import '../search_view_model.dart';
import 'search_keys.dart';

/// The search screen.
///
/// Search field, type chips below it. Per hit: symbol tile, title with mono number,
/// **snippet with the match highlighted**, below it the location.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _input = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    super.dispose();
  }

  /// "**'kin' finds while typing**" — so search while typing, but do not send a call on
  /// every keystroke.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => ref.read(searchViewModelProvider.notifier).search(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final header = PageHeader(
      title: L.of(context).searchTitle,
      // Search is opened via `go` and therefore does not sit on a stack —
      // `pop` would have nothing to go back to. So it goes to the start.
      onBack: () => Navigator.of(context).canPop()
          ? Navigator.of(context).pop()
          : const HomeRoute().go(context),
    );
    return ref
        .watch(searchViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(header: header, error: error),
          data: (state) {
            final l = L.of(context);
            final padding = Breakpoint.of(context).pagePadding;
            final outcome = state.outcome;

            return HiwiskiPage(
              // A search under way — a command running, not the state still coming.
              loading: state.busy,
              header: header,
              body: Column(
                crossAxisAlignment: .stretch,
                children: [
                  Padding(
                    padding: padding,
                    child: SizedBox(
                      height: HiwiskiMetrics.searchHeight,
                      child: ListenableBuilder(
                        // The clear button follows the text at once, not only once the
                        // search ran.
                        listenable: _input,
                        builder: (context, _) => TextField(
                          key: SearchKeys.searchInput,
                          controller: _input,
                          autofocus: true,
                          textInputAction: .search,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: context.scheme.surfaceContainerHigh,
                            hintText: l.searchHint,
                            prefixIcon: const Icon(HiwiskiSymbols.search),
                            suffixIcon: _input.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(HiwiskiSymbols.close),
                                    tooltip: l.searchClear,
                                    onPressed: () {
                                      // The pending term must not come back: `clear` does
                                      // not fire `onChanged`, and "arzt" showed its hits
                                      // under the emptied field.
                                      _debounce?.cancel();
                                      _input.clear();
                                      ref
                                          .read(
                                            searchViewModelProvider.notifier,
                                          )
                                          .search('');
                                    },
                                  ),
                            border: const OutlineInputBorder(
                              borderRadius: .all(
                                .circular(HiwiskiMetrics.radiusSearch),
                              ),
                              borderSide: .none,
                            ),
                            enabledBorder: const OutlineInputBorder(
                              borderRadius: .all(
                                .circular(HiwiskiMetrics.radiusSearch),
                              ),
                              borderSide: .none,
                            ),
                          ),
                          onChanged: _onChanged,
                          onSubmitted: (value) => ref
                              .read(searchViewModelProvider.notifier)
                              .search(value),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: padding.add(
                      const .symmetric(vertical: HiwiskiMetrics.space8),
                    ),
                    child: Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        Wrap(
                          spacing: HiwiskiMetrics.space8,
                          runSpacing: HiwiskiMetrics.space8,
                          children: [
                            for (final type in SearchType.values)
                              FilterPill(
                                label: _label(l, type),
                                selected: state.types.contains(type),
                                onTap: () => ref
                                    .read(searchViewModelProvider.notifier)
                                    .toggleType(type),
                              ),
                            FilterPill(
                              key: SearchKeys.searchIncludeArchive,
                              label: l.searchIncludeArchive,
                              selected: state.includeArchived,
                              onTap: () => ref
                                  .read(searchViewModelProvider.notifier)
                                  .toggleArchived(),
                            ),
                          ],
                        ),
                        const SizedBox(height: HiwiskiMetrics.space8),
                        TagFilterBar(
                          tags: state.tags,
                          selected: state.tagFilter,
                          onToggle: (id) => ref
                              .read(searchViewModelProvider.notifier)
                              .toggleTag(id),
                          onClear: () => ref
                              .read(searchViewModelProvider.notifier)
                              .clearTags(),
                        ),
                      ],
                    ),
                  ),
                  // **Offline** the client searches what is on the device — with an
                  // honest note saying so.
                  if (outcome != null && outcome.offline)
                    Padding(
                      padding: padding,
                      child: NoticeBar(
                        icon: HiwiskiSymbols.cloudOff,
                        text: l.searchOffline,
                        background: context.scheme.surfaceContainerHighest,
                        foreground: context.scheme.onSurfaceVariant,
                      ),
                    ),
                  if (state.failure case final failure?)
                    Padding(
                      padding: padding,
                      child: NoticeBar.error(
                        context,
                        text: failureText(context, failure),
                        onRetry: () =>
                            ref.read(searchViewModelProvider.notifier).retry(),
                      ),
                    ),
                  Expanded(
                    child: switch (outcome) {
                      null when state.failure != null =>
                        const SizedBox.shrink(),
                      null => EmptyState(
                        icon: HiwiskiSymbols.search,
                        message: l.searchStart,
                      ),
                      final found when state.nothing => EmptyState(
                        icon: HiwiskiSymbols.search,
                        // Offline, an empty result means "not found here", not
                        // "does not exist".
                        message: found.offline
                            ? l.searchNothingHere
                            : l.searchNothing,
                      ),
                      final found => ListView(
                        padding: padding.add(
                          const .only(bottom: HiwiskiMetrics.space32),
                        ),
                        children: [
                          // **An entered number jumps straight there.**
                          if (found.jumpTo case final jump?)
                            Card(
                              color: context.scheme.primaryContainer,
                              child: ListTile(
                                leading: const Icon(
                                  HiwiskiSymbols.arrowForward,
                                ),
                                title: Text(
                                  l.searchJumpTo(jump.entityKey ?? jump.title),
                                ),
                                subtitle: Text(jump.title),
                                onTap: () => _open(jump),
                              ),
                            ),
                          for (final hit in state.hits)
                            _Hit(
                              hit: hit,
                              term: state.term,
                              recipe: state.recipes.contains(hit.itemId),
                              onTap: () => _open(hit),
                            ),
                        ],
                      ),
                    },
                  ),
                ],
              ),
            );
          },
        );
  }

  /// The jump **to the hit**, not just into its area.
  ///
  /// `TD-14` jumps straight there — and the same rule
  /// applies to a reference chip. That is why it lives in one place, in `core/routing`.
  void _open(SearchHitView hit) {
    // Navigation: nothing to wait for and nothing that fails.
    openItem(context, ref, itemType: hit.itemType, itemId: hit.itemId).ignore();
  }
}

String _label(L l, SearchType type) => switch (type) {
  .events => l.searchTypeEvents,
  .todos => l.searchTypeTodos,
  .wiki => l.searchTypeWiki,
  .recipes => l.searchTypeRecipes,
};

class _Hit extends StatelessWidget {
  const _Hit({
    required this.hit,
    required this.term,
    required this.onTap,
    required this.recipe,
  });

  final SearchHitView hit;
  final String term;
  final bool recipe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const .symmetric(vertical: HiwiskiMetrics.space10),
        child: Row(
          crossAxisAlignment: .start,
          spacing: HiwiskiMetrics.space12,
          children: [
            Container(
              width: HiwiskiMetrics.tileSize,
              height: HiwiskiMetrics.tileSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.scheme.surfaceContainer,
                borderRadius: const .all(.circular(HiwiskiMetrics.radiusMenu)),
              ),
              child: Icon(
                recipe ? HiwiskiSymbols.restaurant : _icon(hit.itemType),
                size: HiwiskiMetrics.icon22,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          hit.title,
                          style: context.texts.bodyLarge?.copyWith(
                            fontWeight: .w600,
                          ),
                          overflow: .ellipsis,
                        ),
                      ),
                      if (hit.entityKey case final key?) ...[
                        const SizedBox(width: HiwiskiMetrics.space8),
                        Text(key, style: tokens.text.entityKey),
                      ],
                      if (hit.archived) ...[
                        const SizedBox(width: HiwiskiMetrics.space8),
                        const ArchivedChip(),
                      ],
                    ],
                  ),
                  if (hit.snippet case final snippet?)
                    _Highlighted(text: snippet, term: term),
                  if (hit.context case final context_?)
                    Text(
                      context_,
                      style: context.texts.bodySmall?.copyWith(
                        color: context.scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _icon(String itemType) => switch (itemType) {
    EntityTypes.event => HiwiskiSymbols.calendarMonth,
    EntityTypes.todo => HiwiskiSymbols.checklist,
    EntityTypes.todoList => HiwiskiSymbols.formatListBulleted,
    EntityTypes.wikiPage => HiwiskiSymbols.description,
    _ => HiwiskiSymbols.search,
  };
}

/// The snippet with the match highlighted.
///
/// Via `TextStyle.background` and **not** as a `WidgetSpan`, because a snippet has to
/// be able to wrap in the middle of a sentence.
class _Highlighted extends StatelessWidget {
  const _Highlighted({required this.text, required this.term});

  final String text;
  final String term;

  @override
  Widget build(BuildContext context) {
    final ranges = highlightRanges(text, term);
    final base = context.texts.bodySmall?.copyWith(
      color: context.scheme.onSurfaceVariant,
    );
    if (ranges.isEmpty) {
      return Text(text, style: base, maxLines: 2, overflow: .ellipsis);
    }

    final marked = context.tokens.highlight;
    final spans = <TextSpan>[];
    int at = 0;
    for (final (from, to) in ranges) {
      if (from > at) {
        spans.add(TextSpan(text: text.substring(at, from), style: base));
      }
      spans.add(
        TextSpan(
          text: text.substring(from, to),
          style: base?.copyWith(
            background: Paint()..color = marked.background,
            color: marked.foreground,
          ),
        ),
      );
      at = to;
    }
    if (at < text.length) {
      spans.add(TextSpan(text: text.substring(at), style: base));
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: 2,
      overflow: .ellipsis,
    );
  }
}
