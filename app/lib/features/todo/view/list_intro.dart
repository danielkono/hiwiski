import 'package:flutter/material.dart';

import '../../../components/rich_text/view/rich_markdown.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/ui/archived_banner.dart';
import '../../../domain/links/link_index.dart';
import '../../../domain/todo/todo_items.dart';

/// What the list is for, above its entries — links in it work like everywhere. Only
/// where there is something to say: [shows].
class ListIntro extends StatelessWidget {
  const ListIntro({
    super.key,
    required this.list,
    required this.archivedBy,
    required this.onRestore,
    required this.onOpenLink,
    this.onToggleTask,
  });

  /// Ticks the n-th box of the description; `null` for whoever may not write.
  final ValueChanged<int>? onToggleTask;

  /// Whether [list] has an intro: a description, or the archive banner.
  static bool shows(TodoList list) =>
      (list.description?.trim() ?? '').isNotEmpty || list.archivedAt != null;

  final TodoList list;
  final String? archivedBy;
  final VoidCallback? onRestore;
  final ValueChanged<LinkItem>? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final description = list.description?.trim() ?? '';
    final archivedAt = list.archivedAt;
    return Padding(
      padding: const .only(bottom: HiwiskiMetrics.space12),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          if (archivedAt != null)
            ArchivedBanner(
              archivedAt: archivedAt,
              archivedBy: archivedBy,
              onRestore: onRestore,
            ),
          if (archivedAt != null && description.isNotEmpty)
            const SizedBox(height: HiwiskiMetrics.space12),
          if (description.isNotEmpty)
            // Read like a wiki page: headings, lists, chips, images, boxes to tick.
            RichMarkdown(
              text: description,
              onOpen: onOpenLink ?? (_) {},
              onToggleTask: onToggleTask,
            ),
        ],
      ),
    );
  }
}
