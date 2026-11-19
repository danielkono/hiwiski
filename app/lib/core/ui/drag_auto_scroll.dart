import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme/hiwiski_metrics.dart';

/// Scrolls a list while something dragged is held near its top or bottom edge — so a
/// long list can be crossed with one hand, without a second finger.
///
/// **The closer to the edge, the faster**: nothing where the edge zone begins, full
/// speed at the edge and beyond it, rising with the square in between — a little into
/// the zone creeps, so a target right next to the edge can still be hit. Flutter's own
/// `EdgeDraggingAutoScroller` speeds up over 20 pixels only and then stays at one
/// speed.
class DragAutoScroll {
  /// Pixels per second at the edge.
  static const _maxSpeed = 1800.0;
  static const _tick = Duration(milliseconds: 16);

  Timer? _timer;
  ScrollableState? _scrollable;

  /// Pixels per second, negative upwards.
  double _velocity = 0;

  /// The pointer moved to [pointer] (global) while dragging inside the scrollable
  /// around [context].
  void update(BuildContext context, Offset pointer) {
    final scrollable = Scrollable.maybeOf(context);
    final box = scrollable?.context.findRenderObject();
    if (scrollable == null || box is! RenderBox || !box.hasSize) {
      stop();
      return;
    }
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    // A short list keeps a middle where nothing scrolls.
    final edge = HiwiskiMetrics.dragAutoScrollEdge.clamp(
      0.0,
      box.size.height / 3,
    );

    final double depth;
    if (pointer.dy < top + edge) {
      depth = -((top + edge - pointer.dy) / edge).clamp(0.0, 1.0);
    } else if (pointer.dy > bottom - edge) {
      depth = ((pointer.dy - (bottom - edge)) / edge).clamp(0.0, 1.0);
    } else {
      depth = 0;
    }

    _scrollable = scrollable;
    _velocity = depth.sign * depth * depth * _maxSpeed;
    if (_velocity == 0) {
      stop();
    } else {
      _timer ??= Timer.periodic(_tick, (_) => _step());
    }
  }

  void _step() {
    final scrollable = _scrollable;
    if (scrollable == null || !scrollable.mounted) {
      stop();
      return;
    }
    final position = scrollable.position;
    final next = (position.pixels + _velocity * _tick.inMicroseconds / 1e6)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (next != position.pixels) position.jumpTo(next);
  }

  /// The drag ended, or the pointer left the edge zone.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _velocity = 0;
  }
}
