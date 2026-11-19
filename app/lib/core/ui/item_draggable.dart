import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'renamable_row.dart';

/// A row or card that can be dragged: on touch after a long press — otherwise every
/// swipe through a list or the board's pages would pick one up — with the mouse at
/// once, under a grab cursor.
///
/// **By touch it is lifted only once the held finger moves.** The long press alone
/// keeps it where it is: no feedback under the finger, no faded row, no drop targets
/// opening up. Holding to edit a title used to lift the row and put it back the moment
/// the finger let go — the whole list flickered. The hold takes the gesture from the
/// list's scrolling and gives a tick; moving on lifts the row. [liftsOnHold] keeps
/// Flutter's own behaviour — lifted at the long press — for whoever needs to know of
/// the hold itself (the week's timeline opens its card there).
///
/// **It stays alive while it is dragged.** Flutter's [Draggable] reports moves and the
/// end of a drag only while its own widget is mounted. A list that scrolled the held
/// row out of sight threw that widget away: the auto-scroll got no more moves and
/// stopped, and the drag never ended — the row stayed faded, the drop targets stayed
/// up. While held it keeps the list item it sits in, as a keep-alive.
///
/// **Held and let go without moving, it edits the title** of the [RenamableRow]
/// around it: by touch the long press is the drag's, and the row's own long press
/// never comes. While the title is edited the row does not move.
///
/// The shopping list and the board each had their own copy of this pair.
class ItemDraggable<T extends Object> extends StatefulWidget {
  const ItemDraggable({
    super.key,
    required this.data,
    required this.feedback,
    required this.childWhenDragging,
    required this.onDragStarted,
    required this.onDragUpdate,
    required this.onDragDone,
    this.liftsOnHold = false,
    required this.child,
  });

  final T data;
  final Widget feedback;
  final Widget childWhenDragging;
  final VoidCallback onDragStarted;
  final DragUpdateCallback onDragUpdate;

  /// Dropped or cancelled.
  final VoidCallback onDragDone;

  /// By touch: lifted at the long press already, not only once the finger moves.
  final bool liftsOnHold;
  final Widget child;

  /// Whether this is a touch platform.
  static bool get touch => switch (defaultTargetPlatform) {
    .android || .iOS => true,
    _ => false,
  };

  /// Whether the long press at [context] picks the row up — then a row's own long
  /// press never comes.
  static bool takesLongPress(BuildContext context) =>
      touch &&
      context.findAncestorStateOfType<_ItemDraggableState<Object>>() != null;

  @override
  State<ItemDraggable<T>> createState() => _ItemDraggableState<T>();
}

class _ItemDraggableState<T extends Object> extends State<ItemDraggable<T>>
    with AutomaticKeepAliveClientMixin {
  bool _held = false;

  /// Held by touch and not lifted yet: let go now, the title is edited.
  bool _armed = false;

  @override
  bool get wantKeepAlive => _held;

  void _started() {
    _armed = false;
    _held = true;
    updateKeepAlive();
    widget.onDragStarted();
  }

  void _done() {
    widget.onDragDone();
    _held = false;
    updateKeepAlive();
  }

  void _released() {
    if (!_armed) return;
    _armed = false;
    RenamableRow.maybeOf(context)?.edit();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final widget = this.widget;
    // Not taken away while the title is edited: the field would go with it.
    final drags = RenamableRow.editing(context) ? 0 : null;
    if (!ItemDraggable.touch) {
      return Draggable<T>(
        data: widget.data,
        maxSimultaneousDrags: drags,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: widget.feedback,
        childWhenDragging: widget.childWhenDragging,
        onDragStarted: _started,
        onDragUpdate: widget.onDragUpdate,
        onDragEnd: (_) => _done(),
        onDraggableCanceled: (_, _) => _done(),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: widget.child,
        ),
      );
    }
    if (widget.liftsOnHold) {
      return LongPressDraggable<T>(
        data: widget.data,
        maxSimultaneousDrags: drags,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: widget.feedback,
        childWhenDragging: widget.childWhenDragging,
        onDragStarted: _started,
        onDragUpdate: widget.onDragUpdate,
        onDragEnd: (_) => _done(),
        onDraggableCanceled: (_, _) => _done(),
        child: widget.child,
      );
    }
    return Listener(
      onPointerDown: (_) => _armed = false,
      onPointerUp: (_) => _released(),
      onPointerCancel: (_) => _armed = false,
      child: _HoldThenMoveDraggable<T>(
        data: widget.data,
        maxSimultaneousDrags: drags,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: widget.feedback,
        childWhenDragging: widget.childWhenDragging,
        onHeld: () => _armed = true,
        onDragStarted: _started,
        onDragUpdate: widget.onDragUpdate,
        onDragEnd: (_) => _done(),
        onDraggableCanceled: (_, _) => _done(),
        child: widget.child,
      ),
    );
  }
}

/// A [Draggable] that a long press takes hold of and moving the finger then lifts.
class _HoldThenMoveDraggable<T extends Object> extends Draggable<T> {
  const _HoldThenMoveDraggable({
    super.data,
    super.maxSimultaneousDrags,
    super.dragAnchorStrategy,
    required super.feedback,
    super.childWhenDragging,
    required this.onHeld,
    super.onDragStarted,
    super.onDragUpdate,
    super.onDragEnd,
    super.onDraggableCanceled,
    required super.child,
  });

  /// The long press has come; nothing is lifted yet.
  final VoidCallback onHeld;

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => _HoldThenMoveRecognizer(onHeld: onHeld)..onStart = onStart;
}

const _debugDescription = 'hold then move';

class _HoldThenMoveRecognizer extends MultiDragGestureRecognizer {
  _HoldThenMoveRecognizer({required this.onHeld}) : super(debugOwner: null);

  final VoidCallback onHeld;

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _HoldThenMovePointer(
        event.position,
        event.kind,
        gestureSettings,
        onHeld: onHeld,
      );

  @override
  String get debugDescription => _debugDescription;
}

/// One finger: moved beyond the slop before the long press, it is a scroll and not
/// this; held, it wins the arena — the list no longer scrolls under it — and the drag
/// starts once it moves beyond the slop.
class _HoldThenMovePointer extends MultiDragPointerState {
  _HoldThenMovePointer(
    super.initialPosition,
    super.kind,
    super.gestureSettings, {
    required this.onHeld,
  }) {
    _timer = Timer(kLongPressTimeout, _holdPassed);
  }

  final VoidCallback onHeld;
  Timer? _timer;
  bool _held = false;
  GestureMultiDragStartCallback? _starter;

  bool get _beyondSlop =>
      (pendingDelta?.distance ?? 0) > computeHitSlop(kind, gestureSettings);

  void _holdPassed() {
    _timer = null;
    _held = true;
    resolve(GestureDisposition.accepted);
    unawaited(HapticFeedback.selectionClick());
    onHeld();
    _maybeStart();
  }

  void _maybeStart() {
    final starter = _starter;
    if (!_held || starter == null || !_beyondSlop) return;
    _starter = null;
    starter(initialPosition);
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    _starter = starter;
    _maybeStart();
  }

  @override
  void checkForResolutionAfterMove() {
    if (_held) {
      _maybeStart();
    } else if (_timer != null && _beyondSlop) {
      _timer?.cancel();
      _timer = null;
      resolve(GestureDisposition.rejected);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
