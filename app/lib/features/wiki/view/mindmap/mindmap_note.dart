import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../components/links/view/linked_markdown.dart';
import '../../../../components/rich_text/view/image_stack.dart';
import '../../../../core/routing/item_navigation.dart';
import '../../../../domain/wiki/mindmap.dart';
import '../../../../domain/wiki/page_images.dart';

/// A note on the canvas, rendered as a page renders its text: Markdown with link chips
/// that open their target, pictures on lines of their own as pictures. Read-only: a
/// note is written in its own sheet.
class MindmapNote extends ConsumerWidget {
  const MindmapNote({super.key, required this.node, required this.ink});

  final MindmapNode node;

  /// The text colour on the note's surface.
  final Color ink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final style = DefaultTextStyle.of(context).style;
    final sheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: style,
      h1: theme.textTheme.titleLarge?.copyWith(color: ink),
      h2: theme.textTheme.titleMedium?.copyWith(color: ink),
      h3: theme.textTheme.titleSmall?.copyWith(color: ink),
      listBullet: style,
      blockquote: style,
    );
    final parts = <Widget>[
      for (final segment in pageSegments(node.text))
        switch (segment) {
          ImageGroup(:final imageIds) => ImageStack(imageIds: imageIds),
          TextSegment(:final markdown) => LinkedMarkdown(
            data: markdown,
            selectable: false,
            styleSheet: sheet,
            onOpen: (target) => openLinkTarget(context, ref, target),
          ),
        },
    ];
    return SingleChildScrollView(
      // The note is as large as it was drawn; what does not fit is cut, not scrolled —
      // a drag on it moves the element.
      physics: const NeverScrollableScrollPhysics(),
      child: Column(crossAxisAlignment: .stretch, children: parts),
    );
  }
}
