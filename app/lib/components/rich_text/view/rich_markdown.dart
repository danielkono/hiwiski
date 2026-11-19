import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../core/theme/hiwiski_tokens.dart';
import '../../../domain/links/link_index.dart';
import '../../../domain/wiki/markdown_editing.dart';
import '../../../domain/wiki/page_images.dart';
import '../../links/view/linked_markdown.dart';
import 'image_stack.dart';

/// A text as a wiki page reads: Markdown, links as chips, images on lines of their
/// own as images and stacks, boxes to tick — for a task's description and an event's
/// note as for a page. One column; a page's long text is built in
/// blocks by the page itself.
class RichMarkdown extends StatelessWidget {
  const RichMarkdown({
    super.key,
    required this.text,
    required this.onOpen,
    this.onToggleTask,
  });

  final String text;
  final ValueChanged<LinkItem> onOpen;

  /// Ticks the n-th box of the text; `null` where the reader may not.
  final ValueChanged<int>? onToggleTask;

  @override
  Widget build(BuildContext context) {
    final styleSheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: context.tokens.text.prose,
      code: context.tokens.text.monoSmall,
    );
    final onToggle = onToggleTask;
    final parts = <Widget>[];
    // A box's number counts across the images between the texts.
    int boxes = 0;
    for (final segment in pageSegments(text)) {
      switch (segment) {
        case ImageGroup(:final imageIds):
          parts.add(ImageStack(imageIds: imageIds));
        case TextSegment(:final markdown):
          final before = boxes;
          boxes += taskCount(markdown);
          parts.add(
            LinkedMarkdown(
              data: markdown,
              onOpen: onOpen,
              onToggleTask: onToggle == null
                  ? null
                  : (index) => onToggle(before + index),
              styleSheet: styleSheet,
            ),
          );
      }
    }
    return Column(crossAxisAlignment: .stretch, children: parts);
  }
}
