import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../components/links/view/link_preview.dart';
import '../../../../core/routing/item_navigation.dart';
import '../../../../domain/links/link_index.dart';

/// A link element showing its target's content: the target as its preview in a sheet
/// shows it — title, number, its page — scrolled within the element where it is
/// longer. A tap on the title or its symbol opens that preview, and from there the
/// target; no button takes the room of the content.
class MindmapLinkContent extends ConsumerWidget {
  const MindmapLinkContent({super.key, required this.item, this.textScale = 1});

  final LinkItem item;

  /// The element's text size, as a factor on the content's own: the preview brings
  /// its styles along, and the element's size would not reach them otherwise.
  final double textScale;

  /// Whether [context] lies within a target's content shown on a map — where a map
  /// in it shows its links by their titles: the map linking its own page would show
  /// itself in itself, without end.
  static bool within(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_WithinContent>() != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: .linear(textScale)),
    child: SingleChildScrollView(
      child: LinkPreview(
        target: item,
        body: _WithinContent(
          child: ItemPreview(itemType: item.itemType, itemId: item.itemId),
        ),
        inline: true,
        // A sheet over the map, not yet a way off it: nothing to wait for.
        onOpenFull: () => unawaited(openLinkTarget(context, ref, item)),
      ),
    ),
  );
}

/// Marks a target's content shown on a map ([MindmapLinkContent.within]).
class _WithinContent extends InheritedWidget {
  const _WithinContent({required super.child});

  @override
  bool updateShouldNotify(_WithinContent oldWidget) => false;
}
