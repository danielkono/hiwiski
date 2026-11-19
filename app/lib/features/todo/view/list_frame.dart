import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/shell/breakpoints.dart';
import '../../../core/ui/info_bar.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/ui/page_header.dart';
import '../../../core/ui/hiwiski_page.dart';
import '../../../core/ui/states.dart';

/// The page of a list of rows — checklist or shopping: the rows, the info area beside
/// them on a wide screen and below them on the phone, the quick entry at the bottom.
class ListFrame extends StatelessWidget {
  const ListFrame({
    super.key,
    required this.header,
    required this.info,
    required this.intro,
    required this.empty,
    required this.emptyIcon,
    required this.rows,
    required this.quickEntry,
    this.controller,
  });

  final PageHeader header;

  final Widget? info;
  final Widget? intro;

  /// Whether the list has no entries — then [rows] is not shown.
  final bool empty;
  final IconData emptyIcon;

  /// The entries, as a sliver: built as they come into view.
  final Widget rows;

  /// The quick entry, docked on the phone; `null` for whoever may not add.
  final Widget Function({required bool docked})? quickEntry;

  /// The rows' scroll position — for following a row just added.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final padding = Breakpoint.of(context).pagePadding;
    final wide = InfoBar.besideContent(context);
    final info = this.info;
    final intro = this.intro;
    final quickEntry = this.quickEntry;

    final emptyState = EmptyState(icon: emptyIcon, message: l.todoListEmpty);
    final content = switch ((empty, !wide && info != null)) {
      // On the phone the info area sits below the rows — with no rows it has to
      // stay as well: without it an empty list could not be renamed, archived,
      // deleted or turned into a board.
      (true, true) => CustomScrollView(
        slivers: [
          SliverPadding(
            padding: padding.add(const .only(bottom: HiwiskiMetrics.space20)),
            sliver: SliverMainAxisGroup(
              slivers: [
                if (intro != null) SliverToBoxAdapter(child: intro),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const .symmetric(vertical: HiwiskiMetrics.space32),
                    child: emptyState,
                  ),
                ),
                SliverToBoxAdapter(child: info),
              ],
            ),
          ),
        ],
      ),
      (true, false) => Column(
        crossAxisAlignment: .stretch,
        children: [
          if (intro != null) Padding(padding: padding, child: intro),
          Expanded(child: emptyState),
        ],
      ),
      (false, _) => CustomScrollView(
        controller: controller,
        slivers: [
          SliverPadding(
            padding: padding.add(const .only(bottom: HiwiskiMetrics.space20)),
            sliver: SliverMainAxisGroup(
              slivers: [
                if (intro != null) SliverToBoxAdapter(child: intro),
                rows,
                if (!wide && info != null) SliverToBoxAdapter(child: info),
              ],
            ),
          ),
        ],
      ),
    };

    return HiwiskiPage(
      header: header,
      body: Column(
        crossAxisAlignment: .stretch,
        children: [
          Expanded(
            child: wide
                ? Row(
                    crossAxisAlignment: .stretch,
                    children: [
                      // On the desktop the quick entry sticks to the bottom edge of the
                      // content column, not across the full width.
                      Expanded(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth:
                                  HiwiskiMetrics.listMaxWidth +
                                  2 * HiwiskiMetrics.space32,
                            ),
                            child: Column(
                              crossAxisAlignment: .stretch,
                              children: [
                                Expanded(child: content),
                                if (quickEntry != null)
                                  Padding(
                                    padding: padding.add(
                                      const .only(
                                        bottom: HiwiskiMetrics.space20,
                                      ),
                                    ),
                                    child: quickEntry(docked: false),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      ?info,
                    ],
                  )
                : content,
          ),
          if (!wide && quickEntry != null) quickEntry(docked: true),
        ],
      ),
    );
  }
}
