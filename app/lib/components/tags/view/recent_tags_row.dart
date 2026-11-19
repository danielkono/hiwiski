import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/tag_chips.dart';
import '../tags_view_model.dart';

/// The most recently used tags as a choice below the quick entry: selected ones in color
/// with ✕, the rest outlined. Without tags nothing shows.
class RecentTagsRow extends ConsumerWidget {
  const RecentTagsRow({
    super.key,
    required this.selected,
    required this.onToggle,
  });

  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(tagsViewModelProvider)
      .when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        // Suggestions above the quick entry: none rather than an error line there.
        error: (_, _) => const SizedBox.shrink(),
        data: (state) => _RecentTagsBody(
          onToggle: onToggle,
          selected: selected,
          state: state,
        ),
      );
}

class _RecentTagsBody extends StatelessWidget {
  const _RecentTagsBody({
    required this.onToggle,
    required this.selected,
    required this.state,
  });

  final ValueChanged<String> onToggle;
  final Set<String> selected;
  final TagsState state;

  @override
  Widget build(BuildContext context) {
    final known = state.byId;
    final recent = [
      for (final id in {...selected, ...state.recent}) ?known[id],
    ];
    if (recent.isEmpty) return const SizedBox.shrink();
    final muted = context.scheme.onSurfaceVariant;
    return SingleChildScrollView(
      scrollDirection: .horizontal,
      child: Row(
        children: [
          for (final tag in recent) ...[
            if (selected.contains(tag.id))
              TagChip(tag: tag, onRemove: () => onToggle(tag.id))
            else
              InkWell(
                onTap: () => onToggle(tag.id),
                borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
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
                      color: muted,
                      fontWeight: .w500,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: HiwiskiMetrics.space6),
          ],
        ],
      ),
    );
  }
}
