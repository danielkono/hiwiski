import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A sideways swipe that turns a period — the calendar's week or month — like a
/// page: to the left for the next, to the right for the previous.
///
/// Touch only. With a mouse a horizontal drag is how an event is moved, and the
/// arrows in the period's header are a click away.
class PeriodSwipe extends StatefulWidget {
  const PeriodSwipe({super.key, required this.onShift, required this.child});

  /// `1` for the next period, `-1` for the previous.
  final ValueChanged<int> onShift;

  final Widget child;

  @override
  State<PeriodSwipe> createState() => _PeriodSwipeState();
}

class _PeriodSwipeState extends State<PeriodSwipe> {
  /// How far a slow swipe has to go before it counts: a quarter of the width.
  static const _distanceShare = 0.25;

  double _dx = 0;

  void _end(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final width = context.size?.width ?? 0;
    final dx = _dx;
    _dx = 0;
    final fling = velocity.abs() >= kMinFlingVelocity;
    if (!fling && dx.abs() < width * _distanceShare) return;
    final direction = fling ? velocity : dx;
    widget.onShift(direction < 0 ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    supportedDevices: const {.touch, .stylus},
    // Between the events too, where the week has nothing to hit.
    behavior: .translucent,
    onHorizontalDragStart: (_) => _dx = 0,
    onHorizontalDragUpdate: (details) => _dx += details.primaryDelta ?? 0,
    onHorizontalDragEnd: _end,
    onHorizontalDragCancel: () => _dx = 0,
    child: widget.child,
  );
}
