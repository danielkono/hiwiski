import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/add_tag_chip.dart';
import '../../../core/ui/loading_strip.dart';
import '../../../core/ui/notice_bar.dart';
import '../../../core/ui/tag_chips.dart';
import '../../../domain/tags/tag.dart';
import '../tags_view_model.dart';
import 'tag_widgets.dart';
import '../../../core/ui/tap_target.dart';

/// The "Tags" form field: selected ones as chips with ✕, the rest outlined to
/// tap, "+ Tag" creates one.
class TagField extends ConsumerWidget {
  const TagField({super.key, required this.selected, required this.onChanged});

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(tagsViewModelProvider)
      .when(
        skipLoadingOnReload: true,
        loading: () => const LoadingStrip(loading: true),
        error: (error, _) => NoticeBar.failure(context, error: error),
        data: (state) => _TagFieldBody(
          onChanged: onChanged,
          selected: selected,
          tags: state.ranked,
        ),
      );
}

class _TagFieldBody extends ConsumerWidget {
  const _TagFieldBody({
    required this.onChanged,
    required this.selected,
    required this.tags,
  });

  final ValueChanged<Set<String>> onChanged;
  final Set<String> selected;
  final List<Tag> tags;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    return Column(
      crossAxisAlignment: .start,
      children: [
        Text(l.tagsTitle, style: context.tokens.text.sectionLabel),
        const SizedBox(height: HiwiskiMetrics.space8),
        Wrap(
          spacing: HiwiskiMetrics.space6,
          runSpacing: HiwiskiMetrics.space6,
          // Level with "+ Tag", whose tap target is taller than a chip.
          crossAxisAlignment: .center,
          children: [
            for (final tag in tags)
              if (selected.contains(tag.id))
                TagChip(
                  tag: tag,
                  onRemove: () => onChanged({...selected}..remove(tag.id)),
                )
              else
                TapTarget(
                  onTap: () => onChanged({...selected, tag.id}),
                  child: InkWell(
                    onTap: () => onChanged({...selected, tag.id}),
                    borderRadius: const .all(
                      .circular(HiwiskiMetrics.radiusChip),
                    ),
                    child: Container(
                      padding: const .symmetric(
                        horizontal: HiwiskiMetrics.space10,
                        vertical: HiwiskiMetrics.space4,
                      ),
                      decoration: BoxDecoration(
                        border: .fromBorderSide(
                          BorderSide(color: context.scheme.outline),
                        ),
                        borderRadius: const .all(
                          .circular(HiwiskiMetrics.radiusChip),
                        ),
                      ),
                      child: Text(
                        tag.name,
                        style: context.texts.labelMedium?.copyWith(
                          color: context.scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
            AddTagChip(
              onTap: () async {
                final id = await showNewTagDialog(context, ref);
                if (id != null) onChanged({...selected, id});
              },
            ),
          ],
        ),
      ],
    );
  }
}
