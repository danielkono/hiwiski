import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/add_tag_chip.dart';
import '../../../core/ui/info_section.dart';
import '../../../core/ui/notice_bar.dart';
import '../../../core/ui/tag_chips.dart';
import '../../../domain/tags/tag.dart';
import '../tags_view_model.dart';
import 'tag_widgets.dart';

/// The **Tags** section of the info bar: chips, "+ Tag" dashed.
class TagsSection extends ConsumerWidget {
  const TagsSection({
    super.key,
    required this.raw,
    this.onChanged,
    this.inherited = '',
    this.inheritedFrom,
  });

  final String raw;

  /// Tags that come from elsewhere — an event's calendar. Shown, but not removable here.
  final String inherited;

  /// Where [inherited] come from, for the hint below them ("from Family").
  final String? inheritedFrom;

  /// `null` if the reader may not change the item.
  final ValueChanged<List<String>>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(tagsViewModelProvider)
      .when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (error, _) => NoticeBar.failure(context, error: error),
        data: (state) => _TagsSectionBody(
          onChanged: onChanged,
          inheritedFrom: inheritedFrom,
          inherited: inherited,
          raw: raw,
          known: state.byId,
        ),
      );
}

class _TagsSectionBody extends StatelessWidget {
  const _TagsSectionBody({
    required this.onChanged,
    required this.inheritedFrom,
    required this.inherited,
    required this.raw,
    required this.known,
  });

  final ValueChanged<List<String>>? onChanged;
  final String? inheritedFrom;
  final String inherited;
  final String raw;
  final Map<String, Tag> known;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final ids = tagIdsOf(raw);
    final fromElsewhere = tagIdsOf(inherited)
        .where((id) => !ids.contains(id))
        .toList();
    return InfoSection(
      label: l.tagsTitle,
      children: [
        Wrap(
          spacing: HiwiskiMetrics.space6,
          runSpacing: HiwiskiMetrics.space6,
          // "+ Tag" sits in a tap target taller than a chip: centred, it stands level
          // with the tags instead of below them.
          crossAxisAlignment: .center,
          children: [
            for (final id in ids)
              if (known[id] case final tag?) TagChip(tag: tag),
            for (final id in fromElsewhere)
              if (known[id] case final tag?)
                Opacity(opacity: 0.7, child: TagChip(tag: tag)),
            if (onChanged != null)
              AddTagChip(
                onTap: () async {
                  final next = await showTagPicker(context, ids.toSet());
                  if (next != null) onChanged?.call(next.toList());
                },
              ),
          ],
        ),
        if (inheritedFrom case final from? when fromElsewhere.isNotEmpty)
          Padding(
            padding: const .only(top: HiwiskiMetrics.space4),
            child: Text(
              l.tagsInheritedFrom(from),
              style: context.texts.bodySmall?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
