import 'package:flutter/material.dart';

import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../domain/todo/todo_items.dart';

/// A row as a place to drop another one: before it in its upper half, after it in its
/// lower. A line on that edge shows where — drawn over the row, so nothing moves.
class RowDropSlot extends StatefulWidget {
  const RowDropSlot({
    super.key,
    required this.row,
    required this.onDrop,
    required this.child,
  });

  final Todo row;
  final void Function(Todo dragged, {required bool before}) onDrop;
  final Widget child;

  @override
  State<RowDropSlot> createState() => _RowDropSlotState();
}

class _RowDropSlotState extends State<RowDropSlot> {
  /// Where a held row would go: before this one, after it, or — `null` — not here.
  bool? _before;

  void _hover(Offset pointer) {
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    final before = box.globalToLocal(pointer).dy < box.size.height / 2;
    if (before != _before) setState(() => _before = before);
  }

  @override
  Widget build(BuildContext context) {
    final line = BorderSide(
      color: context.scheme.primary,
      width: HiwiskiMetrics.strokeBold,
    );
    return DragTarget<Todo>(
      // Not onto itself.
      onWillAcceptWithDetails: (details) => details.data.id != widget.row.id,
      // The drag anchors at the pointer: the feedback's corner is the finger.
      onMove: (details) {
        if (details.data.id != widget.row.id) _hover(details.offset);
      },
      onLeave: (_) => setState(() => _before = null),
      onAcceptWithDetails: (details) {
        final before = _before ?? true;
        setState(() => _before = null);
        widget.onDrop(details.data, before: before);
      },
      // Always the same box, line or not: a wrapper that came and went would rebuild
      // the row beneath it — and a row being dragged would lose its drag.
      builder: (context, _, _) => DecoratedBox(
        position: .foreground,
        decoration: switch (_before) {
          // The context is BoxBorder: abstract, a shorthand finds no constructor.
          // ignore: many_lints/prefer_shorthands_with_constructors
          true => BoxDecoration(border: Border(top: line)),
          // The context is BoxBorder: abstract, a shorthand finds no constructor.
          // ignore: many_lints/prefer_shorthands_with_constructors
          false => BoxDecoration(border: Border(bottom: line)),
          null => const BoxDecoration(),
        },
        child: widget.child,
      ),
    );
  }
}
