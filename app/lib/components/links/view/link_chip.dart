import 'package:flutter/material.dart';

import '../../../core/common/wire.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../domain/links/link_index.dart';

/// The icon of the target type — a link carries it so you know where it leads before
/// tapping.
IconData linkItemIcon(String itemType) => switch (itemType) {
  EntityTypes.todo => HiwiskiSymbols.checklist,
  EntityTypes.todoList => HiwiskiSymbols.formatListBulleted,
  EntityTypes.event => HiwiskiSymbols.calendarMonth,
  EntityTypes.wikiPage => HiwiskiSymbols.description,
  _ => HiwiskiSymbols.link,
};

String linkItemTypeLabel(L l, String itemType) => switch (itemType) {
  EntityTypes.todo => l.linkTypeTodo,
  EntityTypes.todoList => l.linkTypeTodoList,
  EntityTypes.event => l.linkTypeEvent,
  EntityTypes.wikiPage => l.linkTypeWikiPage,
  _ => itemType,
};

/// The link chip in the text.
///
/// **Both notations become this one chip**: the target type's icon and the **current**
/// title — not the text that applied when it was written.
/// A tap opens the target.
///
/// Icon size 16, because it sits inline in the text.
class LinkChip extends StatelessWidget {
  const LinkChip({super.key, required this.target, this.onOpen});

  final LinkItem target;
  final ValueChanged<LinkItem>? onOpen;

  @override
  Widget build(BuildContext context) {
    final chip = DecoratedBox(
      decoration: BoxDecoration(
        color: context.scheme.secondaryContainer,
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
      ),
      child: Padding(
        padding: const .symmetric(
          horizontal: HiwiskiMetrics.space6,
          vertical: HiwiskiMetrics.space2,
        ),
        child: Row(
          mainAxisSize: .min,
          spacing: HiwiskiMetrics.space4,
          children: [
            Icon(
              linkItemIcon(target.itemType),
              size: HiwiskiMetrics.icon16,
              color: context.scheme.onSecondaryContainer,
            ),
            // Flexible and cut off: in a sentence or a comment the chip is as wide as
            // the line at most — a long title ran out of the container before.
            Flexible(
              child: Text(
                target.title,
                maxLines: 1,
                overflow: .ellipsis,
                style: context.texts.labelLarge?.copyWith(
                  color: context.scheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final onOpen = this.onOpen;
    if (onOpen == null) return chip;
    return InkWell(
      onTap: () => onOpen(target),
      borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
      child: chip,
    );
  }
}
