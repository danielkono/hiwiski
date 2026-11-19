import 'package:flutter/material.dart';

import '../shell/breakpoints.dart';
import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_tokens.dart';
import 'content_width.dart';
import 'info_delete_section.dart';

/// The info bar.
///
/// **On desktop a column on the right** (260 wide, line on the left, gap 24), **on the
/// phone a section below the content** with a line above it. The screen only decides
/// *where* it puts it — into the content flow or next to it — by [besideContent]; how
/// it looks, the bar decides itself from the same answer.
///
/// It is the place where sharing, links, tags and history become visible
/// **together**. In an earlier version the same information was spread across four screens, and
/// nobody ever opened three of them.
class InfoBar extends StatelessWidget {
  const InfoBar({super.key, required this.sections});

  final List<Widget> sections;

  /// Whether the bar stands beside the content: on a wide window, and only while the
  /// content keeps its reading width next to it. The window alone does not say that —
  /// on an iPad upright the drawer and the wiki's tree take most of it
  /// ([ContentWidth]).
  static bool besideContent(BuildContext context) =>
      Breakpoint.of(context).isWide &&
      ContentWidth.of(context) >=
          HiwiskiMetrics.pagePaddingWide.horizontal +
              HiwiskiMetrics.readingMinWidth +
              HiwiskiMetrics.space24 +
              HiwiskiMetrics.infoRailWidth;

  @override
  Widget build(BuildContext context) {
    final divider = context.tokens.divider;
    final content = Column(
      crossAxisAlignment: .stretch,
      children: [
        for (final (index, section) in sections.indexed) ...[
          section,
          // The actions at the bottom (archive, delete) follow the history's button as
          // closely as they follow each other — one stack of buttons, not a new section.
          if (index + 1 < sections.length &&
              sections[index + 1] is InfoDeleteSection)
            const SizedBox.shrink()
          else
            const SizedBox(height: HiwiskiMetrics.space24),
        ],
      ],
    );

    if (!besideContent(context)) {
      return Padding(
        padding: const .only(top: HiwiskiMetrics.space24),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: HiwiskiMetrics.space20,
          children: [
            Divider(height: HiwiskiMetrics.hairline, color: divider),
            content,
          ],
        ),
      );
    }

    return Container(
      width: HiwiskiMetrics.infoRailWidth,
      decoration: BoxDecoration(
        // The context is BoxBorder: abstract, a shorthand finds no constructor.
        // ignore: many_lints/prefer_shorthands_with_constructors
        border: Border(left: BorderSide(color: divider)),
      ),
      padding: const .only(
        left: HiwiskiMetrics.space24,
        right: HiwiskiMetrics.space16,
        top: HiwiskiMetrics.space16,
        bottom: HiwiskiMetrics.space32,
      ),
      child: SingleChildScrollView(child: content),
    );
  }
}
