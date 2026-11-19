import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../components/links/view/linked_markdown.dart';
import '../../../../../components/rich_text/view/image_stack.dart';
import '../../../../../core/routing/item_navigation.dart';
import '../../../../../domain/wiki/markdown_editing.dart';
import '../../../../../domain/wiki/page_images.dart';
import '../../../../../domain/wiki/wiki_page.dart';
import '../../page_view_model.dart';

/// One Markdown block of a page that reads as text.
///
/// **Both spellings become the same chip** with the current title.
/// Between two blocks the gap Markdown puts between two of its
/// own.
class TextBlock extends ConsumerWidget {
  const TextBlock({
    super.key,
    required this.page,
    required this.chunk,
    required this.first,
    required this.offset,
    required this.writable,
    required this.styleSheet,
  });

  final WikiPage page;
  final String chunk;
  final bool first;

  /// How many boxes the blocks before this one hold.
  final int offset;
  final bool writable;
  final MarkdownStyleSheet styleSheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Images on lines of their own come out of the text and show as images or stacks.
    // The box numbers count on across them.
    final segments = pageSegments(chunk);
    int boxes = offset;
    final parts = <Widget>[];
    for (final segment in segments) {
      switch (segment) {
        case ImageGroup(:final imageIds):
          parts.add(ImageStack(imageIds: imageIds));
        case TextSegment(:final markdown):
          final before = boxes;
          boxes += taskCount(markdown);
          parts.add(
            LinkedMarkdown(
              data: markdown,
              onOpen: (target) => openLinkTarget(context, ref, target),
              // Tick a box right on the page — only for whoever may write.
              onToggleTask: writable
                  ? (index) => ref
                        .read(pageViewModelProvider(page.id).notifier)
                        .toggleTask(page, before + index)
                  : null,
              styleSheet: styleSheet,
            ),
          );
      }
    }
    return Padding(
      padding: .only(top: first ? 0 : styleSheet.blockSpacing ?? 0),
      child: parts.length == 1
          ? parts.single
          : Column(crossAxisAlignment: .stretch, children: parts),
    );
  }
}
