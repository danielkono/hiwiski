import 'package:flutter/material.dart';

import '../../components/sync_banner/view/sync_banner.dart';
import '../../domain/tags/tag.dart';
import '../l10n/generated/app_localizations.dart';
import '../shell/breakpoints.dart';
import '../theme/hiwiski_metrics.dart';
import 'embedded_page.dart';
import 'loading_strip.dart';
import 'notice_bar.dart';
import 'page_header.dart';
import 'pull_filter.dart';
import 'tag_filter_bar.dart';

/// The frame of every screen inside the app shell: loading strip, header, sync
/// banner, filter bar, content — always in this order.
///
/// The screen says **what** it has; how it is laid out is decided here. Whether a
/// screen filters is one line — its [filter] — and nowhere else: no list of routes
/// has to know about it.
///
/// The sync banner is not the screen's choice: **offline and conflict belong on every
/// screen** — a conflict nobody sees is data loss.
class HiwiskiPage extends StatelessWidget {
  const HiwiskiPage({
    super.key,
    required this.header,
    required this.body,
    this.loading = false,
    this.filter,
    this.floatingActionButton,
  }) : _withContent = true;

  /// The screen while its state is still coming: header and strip, no content — never
  /// a spinner in its place (`LoadingStrip`).
  const HiwiskiPage.loading({super.key, required this.header})
    : body = const SizedBox.shrink(),
      loading = true,
      filter = null,
      floatingActionButton = null,
      _withContent = false;

  /// The screen whose state failed: header and the error line, with "Retry" when
  /// [onRetry] is given.
  HiwiskiPage.error({
    super.key,
    required this.header,
    required Object error,
    VoidCallback? onRetry,
  }) : body = _Failed(error: error, onRetry: onRetry),
       loading = false,
       filter = null,
       floatingActionButton = null,
       _withContent = false;

  final PageHeader header;
  final Widget body;

  /// Shows the strip above the header. It is always there, loading or not, so that
  /// the header does not jump when it appears.
  final bool loading;

  /// The bar above the content: pulls away on the phone, always there from 600.
  final PageFilter? filter;

  final Widget? floatingActionButton;

  /// False for [HiwiskiPage.loading] and [HiwiskiPage.error].
  final bool _withContent;

  static const _frameWithoutContent = ValueKey('hiwiski-page-without-content');

  @override
  Widget build(BuildContext context) {
    final filter = this.filter;
    final content = filter == null || !filter.visible
        ? body
        : PullToRevealFilter(
            hint: switch (filter) {
              TagPageFilter() => L.of(context).pullForFilter,
              CustomPageFilter(:final hint) => hint,
            },
            forceShown: switch (filter) {
              TagPageFilter() => false,
              CustomPageFilter(:final forceShown) => forceShown,
            },
            padding: Breakpoint.of(context).pagePadding
                .add(const .only(bottom: HiwiskiMetrics.space12)),
            // At least as high as the tallest bar: tag chips are lower than the
            // start screen's button, and the content moved when switching.
            filter: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: HiwiskiMetrics.filterBarHeight,
              ),
              // Centered in the height, stretched across: Align does only the first.
              // ignore: many_lints/avoid_single_child_in_multi_child_widgets
              child: Column(
                mainAxisAlignment: .center,
                crossAxisAlignment: .stretch,
                children: [
                  switch (filter) {
                    TagPageFilter(
                      :final tags,
                      :final selected,
                      :final onToggle,
                      :final onClear,
                    ) =>
                      TagFilterBar(
                        tags: tags,
                        selected: selected,
                        onToggle: onToggle,
                        onClear: onClear,
                      ),
                    CustomPageFilter(:final bar) => bar,
                  },
                ],
              ),
            ),
            child: body,
          );

    final embedded = EmbeddedPage.of(context);
    return Scaffold(
      // Loading and failed screens get a Scaffold of their own, so the one with the
      // content is new when the content arrives and its floating button is there
      // from the first frame. A Scaffold that stays sees the button added later and
      // grows it in. That happened on every screen that builds its content in the
      // place where its loading frame stood, and not on screens that use a widget of
      // their own for the content.
      key: _withContent ? null : _frameWithoutContent,
      body: Column(
        crossAxisAlignment: .stretch,
        children: [
          // Inside another screen the strip lies over the header's top edge and
          // takes no room: the title has to stand level with the row of the panel
          // beside it, and the strip's height put it below.
          if (embedded)
            Stack(
              children: [
                header,
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LoadingStrip(loading: loading),
                ),
              ],
            )
          else ...[
            LoadingStrip(loading: loading),
            header,
            // Once per page: the screen around an embedded one shows it already.
            const SyncBanner(),
          ],
          Expanded(child: content),
        ],
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: Padding(
      padding: Breakpoint.of(context).pagePadding,
      child: NoticeBar.failure(context, error: error, onRetry: onRetry),
    ),
  );
}

/// What sits in a page's filter bar.
sealed class PageFilter {
  const PageFilter({required this.visible});

  /// Hidden, the page keeps its filter — only the bar is not shown.
  final bool visible;
}

/// The tag chips of a filter — nothing else, so that the bar is equally high on every
/// page; a page's own controls go into its header. What they show comes from the
/// screen's ViewModel, which also lets the filter go with the page.
final class TagPageFilter extends PageFilter {
  const TagPageFilter({
    required this.tags,
    required this.selected,
    required this.onToggle,
    required this.onClear,
    super.visible = true,
  });

  final List<Tag> tags;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onClear;
}

/// Anything else in the same place — the start screen's customize controls.
final class CustomPageFilter extends PageFilter {
  const CustomPageFilter({
    required this.bar,
    required this.hint,
    this.forceShown = false,
    super.visible = true,
  });

  final Widget bar;
  final String hint;

  /// Keeps the bar open, e.g. in the start screen's edit mode.
  final bool forceShown;
}
