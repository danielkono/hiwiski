import 'package:flutter/material.dart';

/// A row that can be deleted from right where it is — a task, a card, a comment: its
/// `DeleteHoldButton` slides it aside, fades it and closes the gap — then
/// [onRemoved] takes it out of the list.
class RemovableRow extends StatefulWidget {
  const RemovableRow({super.key, required this.onRemoved, required this.child});

  /// The animation is done: delete the item.
  final VoidCallback onRemoved;
  final Widget child;

  /// The row around [context], if it can be removed.
  static RemovableRowState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<RemovableRowState>();

  @override
  State<RemovableRow> createState() => RemovableRowState();
}

class RemovableRowState extends State<RemovableRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _out = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  /// Sideways first, then the gap closes.
  late final _slide = Tween(begin: Offset.zero, end: const Offset(-0.35, 0))
      .animate(
        CurvedAnimation(
          parent: _out,
          curve: const Interval(0, 0.6, curve: Curves.easeIn),
        ),
      );
  late final _fade = Tween(
    begin: 1.0,
    end: 0.0,
  ).animate(CurvedAnimation(parent: _out, curve: const Interval(0, 0.6)));
  late final _size = Tween(begin: 1.0, end: 0.0).animate(
    CurvedAnimation(
      parent: _out,
      curve: const Interval(0.5, 1, curve: Curves.easeInOut),
    ),
  );

  @override
  void dispose() {
    _out.dispose();
    super.dispose();
  }

  /// Plays the removal, then hands the row over to [RemovableRow.onRemoved].
  Future<void> remove() async {
    if (_out.isAnimating || _out.isCompleted) return;
    await _out.forward();
    if (mounted) widget.onRemoved();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
    sizeFactor: _size,
    alignment: Alignment.topCenter,
    child: FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    ),
  );
}
