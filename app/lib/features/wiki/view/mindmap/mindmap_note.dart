import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../components/links/view/linked_markdown.dart';
import '../../../../components/rich_text/view/image_stack.dart';
import '../../../../core/common/wire.dart';
import '../../../../core/routing/item_navigation.dart';
import '../../../../domain/wiki/mindmap.dart';
import '../../../../domain/wiki/page_images.dart';

/// A note on the canvas, rendered as a page renders its text: Markdown with link chips
/// that open their target, pictures on lines of their own as pictures. Read-only: a
/// note is written in its own sheet.
///
/// Its text stands where [MindmapNode.textAlign] says: across, each line to the left,
/// in the middle or to the right; up and down, at the top, in the middle or at the
/// bottom of what the note has room for. A text taller than the note starts at its
/// top whatever the place: what is cut is its end, not its beginning.
class MindmapNote extends ConsumerWidget {
  const MindmapNote({super.key, required this.node, required this.ink});

  final MindmapNode node;

  /// The text colour on the note's surface.
  final Color ink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final style = DefaultTextStyle.of(context).style;
    final (across, upDown) = _placeOf(node.textAlign);
    final sheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: style,
      h1: theme.textTheme.titleLarge?.copyWith(color: ink),
      h2: theme.textTheme.titleMedium?.copyWith(color: ink),
      h3: theme.textTheme.titleSmall?.copyWith(color: ink),
      listBullet: style,
      blockquote: style,
      textAlign: across,
      h1Align: across,
      h2Align: across,
      h3Align: across,
      h4Align: across,
      h5Align: across,
      h6Align: across,
    );
    final parts = <Widget>[
      for (final segment in pageSegments(node.text))
        switch (segment) {
          // A picture is narrower than a wide note: it stands where the lines do.
          ImageGroup(:final imageIds) => Align(
            alignment: switch (across) {
              .center => Alignment.topCenter,
              .end => AlignmentDirectional.topEnd,
              _ => AlignmentDirectional.topStart,
            },
            child: ImageStack(imageIds: imageIds),
          ),
          TextSegment(:final markdown) => LinkedMarkdown(
            data: markdown,
            selectable: false,
            // As wide as the note, or a short line would stand at its left
            // whatever its place.
            fitContent: false,
            styleSheet: sheet,
            onOpen: (target) => openLinkTarget(context, ref, target),
          ),
        },
    ];
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        // The note is as large as it was drawn; what does not fit is cut, not
        // scrolled — a drag on it moves the element.
        physics: const NeverScrollableScrollPhysics(),
        child: ConstrainedBox(
          // As high as the note at least, so that the text can stand in its middle
          // or at its bottom.
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: upDown,
            crossAxisAlignment: .stretch,
            children: parts,
          ),
        ),
      ),
    );
  }

  /// [align] as the lines' place across and the text's place up and down; an
  /// unknown one, or none, is the top left.
  static (WrapAlignment, MainAxisAlignment) _placeOf(String? align) => (
    switch (align) {
      MindmapTextAligns.topCenter ||
      MindmapTextAligns.center ||
      MindmapTextAligns.bottomCenter => .center,
      MindmapTextAligns.topRight ||
      MindmapTextAligns.middleRight ||
      MindmapTextAligns.bottomRight => .end,
      _ => .start,
    },
    switch (align) {
      MindmapTextAligns.middleLeft ||
      MindmapTextAligns.center ||
      MindmapTextAligns.middleRight => .center,
      MindmapTextAligns.bottomLeft ||
      MindmapTextAligns.bottomCenter ||
      MindmapTextAligns.bottomRight => .end,
      _ => .start,
    },
  );
}
