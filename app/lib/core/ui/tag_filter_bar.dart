import 'package:flutter/material.dart';

import '../../domain/tags/tag.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_tokens.dart';
import 'filter_pill.dart';
import 'hiwiski_sheet.dart';

/// The filter bar: "All" as a filled chip, followed by the tag chips.
/// What it offers and what is selected come from the screen's
/// ViewModel; the bar only shows them.
class TagFilterBar extends StatelessWidget {
  const TagFilterBar({
    super.key,
    required this.tags,
    required this.selected,
    required this.onToggle,
    required this.onClear,
  });

  /// Every tag, in the order that matters to this member ([rankTags]).
  final List<Tag> tags;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final filter = selected;

    // **One line at most** — with many tags the bar used to grow into a block above the
    // content. "All", then what is selected, then the rest by how often and how lately
    // it was used; what does not fit sits behind "+N".
    final ordered = [
      ...tags.where((tag) => filter.contains(tag.id)),
      ...tags.where((tag) => !filter.contains(tag.id)),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final style = context.texts.labelLarge ?? const TextStyle();
        final scale = MediaQuery.textScalerOf(context);
        double width(String label, {bool selected = false}) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: .ltr,
            textScaler: scale,
            maxLines: 1,
          )..layout();
          // Padding 12 + 12 and the outline's 1 + 1 (a Container adds its
          // border to the padding); selected, without an outline, a check
          // 8 + 18 + 4 + 12 instead. Short by the outline, a row of pills ran over
          // its end at some widths.
          return painter.width + (selected ? 42 : 26);
        }

        const gap = HiwiskiMetrics.space8;
        // Room for "+N" selected: it is marked when a selected tag sits behind it.
        final moreWidth = width('+${ordered.length}', selected: true);
        double used = width(l.calAll, selected: filter.isEmpty);
        int shown = 0;
        for (final tag in ordered) {
          final next =
              used + gap + width(tag.name, selected: filter.contains(tag.id));
          final rest = ordered.length - shown - 1;
          if (next + (rest > 0 ? gap + moreWidth : 0) > constraints.maxWidth) {
            break;
          }
          used = next;
          shown++;
        }
        final hidden = ordered.length - shown;
        // On a narrow screen even a selected tag may not fit — then "+N" shows
        // that a filter is on, or the list would look unfiltered.
        final hiddenSelected = ordered
            .skip(shown)
            .any((tag) => filter.contains(tag.id));

        return Row(
          children: [
            FilterPill(
              label: l.calAll,
              selected: filter.isEmpty,
              onTap: onClear,
            ),
            for (final tag in ordered.take(shown)) ...[
              const SizedBox(width: gap),
              FilterPill(
                label: tag.name,
                selected: filter.contains(tag.id),
                onTap: () => onToggle(tag.id),
              ),
            ],
            if (hidden > 0) ...[
              const SizedBox(width: gap),
              FilterPill(
                label: '+$hidden',
                selected: hiddenSelected,
                onTap: () => _showAll(context),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Every tag, to pick from — the ones that did not fit in the line.
  Future<void> _showAll(BuildContext context) {
    final chosen = {...selected};
    return showHiwiskiSheet<void>(
      context: context,
      title: L.of(context).tagsTitle,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Wrap(
          spacing: HiwiskiMetrics.space8,
          runSpacing: HiwiskiMetrics.space8,
          children: [
            for (final tag in tags)
              FilterPill(
                label: tag.name,
                selected: chosen.contains(tag.id),
                onTap: () {
                  onToggle(tag.id);
                  setState(
                    () => chosen.contains(tag.id)
                        ? chosen.remove(tag.id)
                        : chosen.add(tag.id),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
