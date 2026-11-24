import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../components/links/view/linked_flow.dart';
import '../../../../core/common/wire.dart';
import '../../../../core/routing/item_navigation.dart';
import '../../../../core/ui/flowing_text.dart';
import '../../../../domain/wiki/mindmap.dart';
import 'mindmap_element.dart';
import 'mindmap_outline.dart';

/// A note on the canvas: its Markdown with link chips that open their target and
/// pictures, set into lines. Read-only: a note is written in its own sheet.
///
/// Its lines fill what [MindmapNode.textFlow] says: the largest box inside its
/// shape, every line as wide as it; or the shape itself, each line as wide as the
/// shape is at its height. The text stands where [MindmapNode.textAlign] says:
/// across, each line — a list's and a picture's too — to the left, in the middle or
/// to the right; up and down, at the top, in the middle or at the bottom of the
/// room. A text taller than the note starts at its top: what is cut is its end, not
/// its beginning.
class MindmapNote extends ConsumerWidget {
  const MindmapNote({
    super.key,
    required this.node,
    required this.ink,
    this.onToggleTask,
  });

  final MindmapNode node;

  /// The text colour on the note's surface.
  final Color ink;

  /// Ticks or unticks the n-th checkbox of its text — where the map is read and may
  /// be changed, as a page's boxes are; `null`: shown, not tappable.
  final ValueChanged<int>? onToggleTask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final style = DefaultTextStyle.of(context).style;
    // Headings grow with the note's text, as much larger than it as at the medium
    // size: at the theme's own sizes, a heading was smaller than large text.
    final scale = MindmapElementView.textScaleOf(context, node.textSize);
    TextStyle? heading(TextStyle? title) => title?.copyWith(
      color: ink,
      fontSize: switch (title.fontSize) {
        final size? => size * scale,
        null => null,
      },
    );
    final sheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: style,
      h1: heading(theme.textTheme.titleLarge),
      h2: heading(theme.textTheme.titleMedium),
      h3: heading(theme.textTheme.titleSmall),
      listBullet: style,
      blockquote: style,
    );
    return LinkedFlow(
      data: node.text,
      styleSheet: sheet,
      outline: followsShape(node)
          ? MindmapOutline(
              node.effectiveShape,
              pad: MindmapElementView.shapePad,
            )
          : const FlowBox(),
      place: placeOf(node.textAlign),
      onOpen: (target) => openLinkTarget(context, ref, target),
      onToggleTask: onToggleTask,
    );
  }

  /// Whether [node]'s lines fill its shape itself, not the box inside it.
  static bool followsShape(MindmapNode node) =>
      node.textFlow == MindmapTextFlows.shape;

  /// [align] as a place in the room; an unknown one, or none, is the top left.
  static AlignmentDirectional placeOf(String? align) => switch (align) {
    MindmapTextAligns.topCenter => .topCenter,
    MindmapTextAligns.topRight => .topEnd,
    MindmapTextAligns.middleLeft => .centerStart,
    MindmapTextAligns.center => .center,
    MindmapTextAligns.middleRight => .centerEnd,
    MindmapTextAligns.bottomLeft => .bottomStart,
    MindmapTextAligns.bottomCenter => .bottomCenter,
    MindmapTextAligns.bottomRight => .bottomEnd,
    _ => .topStart,
  };
}
