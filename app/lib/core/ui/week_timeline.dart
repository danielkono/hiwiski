import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/calendar/calendar_items.dart';
import '../../domain/calendar/occurrence.dart';
import '../../domain/calendar/reschedule.dart';
import '../../domain/calendar/span_lanes.dart';
import '../../domain/calendar/week_layout.dart';
import '../../domain/common/calendar_days.dart';
import '../common/wire.dart';
import '../l10n/generated/app_localizations.dart';
import '../routing/item_navigation.dart';
import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_tokens.dart';
import 'color_tokens.dart';
import 'item_draggable.dart';

/// The days side by side, their timed events as blocks by time and length, all-day and
/// multi-day ones as bars above the hours.
///
/// **Only the hours that hold something are drawn** ([WeekLayout]): the empty morning
/// and evening are cut off, a long empty stretch in between is skipped and marked with
/// a wavy break. So a week fits at once and one sees what a day holds and how its
/// events stand to each other — on the calendar screen as on a board tile.
///
/// **In the calendar the week is worked in**: a tap into free
/// hours creates an event there, an event is dragged to another time or day — into the
/// band above the hours it becomes an all-day event, out of the band into the hours a
/// timed one —, and hovering over an event (a long press on touch) opens it as a card.
/// All of that only where the callbacks are given; on a board tile and the kiosk the
/// week is read.
class WeekTimeline extends StatefulWidget {
  const WeekTimeline({
    super.key,
    required this.days,
    required this.occurrences,
    required this.calendars,
    this.height,
    this.selected,
    this.onDayTap,
    this.kiosk = false,
    this.alwaysShown,
    this.onSlotTap,
    this.onMove,
    this.canMove,
    this.preview,
  });

  final List<DateTime> days;
  final List<Occurrence> occurrences;
  final Map<String, Calendar> calendars;

  /// The height to fit the hours into; `null` takes a readable default per hour.
  final double? height;

  /// The day marked as chosen (the calendar screen's selected day).
  final DateTime? selected;
  final ValueChanged<DateTime>? onDayTap;

  /// On the wall tablet: larger text, no taps.
  final bool kiosk;

  /// Hours shown even when nothing is in them — room to tap and drop.
  final TimeSegment? alwaysShown;

  /// A tap into free hours: the slot on the 15-minute grid.
  final ValueChanged<WeekSlot>? onSlotTap;

  /// An event dropped on a slot.
  final void Function(Occurrence occurrence, WeekSlot slot)? onMove;

  /// Whether an event may be picked up; without it, every one may.
  final bool Function(Occurrence occurrence)? canMove;

  /// What the card an event grows into on hover or a long press shows below its
  /// title.
  final Widget Function(BuildContext context, Occurrence occurrence)? preview;

  static const _gutter = HiwiskiMetrics.weekGutter;
  static const _barHeight = HiwiskiMetrics.weekBarHeight;
  static const _skipHeight = HiwiskiMetrics.weekBarHeight;

  /// Pixels per minute: below the lower bound text no longer fits a half hour, above
  /// the upper one a short day looks bloated.
  static const _minScale = 0.45;
  static const _maxScale = 1.1;

  @override
  State<WeekTimeline> createState() => _WeekTimelineState();
}

/// What is being dragged, and from where.
class _Drag {
  _Drag(this.occurrence, this.grab, this.origin);

  final Occurrence occurrence;

  /// Where the pointer took hold, inside the block or bar.
  final Offset grab;

  /// Where the drag started, globally — the day it started on counts from there.
  final Offset origin;

  /// Where it would land now.
  WeekSlot? slot;

  /// Moved far enough to be a drag and not a long press that opens the card.
  bool moved = false;
}

class _WeekTimelineState extends State<WeekTimeline> {
  final _hoursKey = GlobalKey();
  final _bandKey = GlobalKey();

  _Drag? _drag;

  /// Where the pointer last went down on a block — the grab of the drag it starts.
  Offset _pointerDown = .zero;
  Offset _pointerDownGlobal = .zero;

  OverlayEntry? _card;
  final _cardKey = GlobalKey<_PreviewCardState>();
  Timer? _hoverTimer;
  Timer? _hideTimer;

  /// Set from the last build: where the hours and the columns are.
  WeekLayout? _layout;
  double _scale = 0;
  double _column = 0;

  bool get _interactive => !widget.kiosk && widget.onMove != null;

  /// Where the now line and today's column stand. Kept here and moved on every full
  /// minute by [_minuteTimer]: nothing else rebuilds the week while it is only looked
  /// at — on the wall tablet, or the calendar left open —, and read from the clock
  /// while building they stood where they were when it was last built.
  DateTime _now = clock.now();
  Timer? _minuteTimer;

  /// Back in the foreground the week is rebuilt at once: while the app is in the
  /// background the platform may hold its timers, and the line would wait for the
  /// next minute that is still pending.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onMinute);
    _scheduleMinute();
  }

  void _scheduleMinute() {
    _minuteTimer?.cancel();
    // What is left of this minute, not the next minute built as a date: on the night
    // the clocks go back, 02:59 is followed by 02:00, and "03:00" is an hour away.
    final intoMinute = Duration(
      seconds: _now.second,
      milliseconds: _now.millisecond,
      microseconds: _now.microsecond,
    );
    _minuteTimer = Timer(const Duration(minutes: 1) - intoMinute, _onMinute);
  }

  void _onMinute() {
    if (!mounted) return;
    setState(() => _now = clock.now());
    _scheduleMinute();
  }

  @override
  void dispose() {
    _minuteTimer?.cancel();
    _lifecycle.dispose();
    _hoverTimer?.cancel();
    _hideTimer?.cancel();
    _card
      ?..remove()
      ..dispose();
    super.dispose();
  }

  bool _mayMove(Occurrence occurrence) =>
      _interactive && (widget.canMove?.call(occurrence) ?? true);

  // --- Geometry ---------------------------------------------------------------------

  /// The column under a global [x], clamped to the week.
  int _dayIndexAt(RenderBox box, double x) {
    final local = box.globalToLocal(Offset(x, 0)).dx;
    return ((local - WeekTimeline._gutter) / _column).floor().clamp(
      0,
      widget.days.length - 1,
    );
  }

  /// The day a dragged event lands on: shifted by as many columns as the pointer went.
  DateTime _dropDay(RenderBox box, _Drag drag, Offset pointer) {
    final shift =
        _dayIndexAt(box, pointer.dx) - _dayIndexAt(box, drag.origin.dx);
    return addDays(startOfDay(drag.occurrence.start), shift);
  }

  WeekSlot? _hoursSlot(_Drag drag, Offset pointer) {
    final box = _hoursKey.currentContext?.findRenderObject();
    final layout = _layout;
    if (box is! RenderBox || layout == null) return null;
    final top = box.globalToLocal(pointer).dy - drag.grab.dy;
    final minute = _minuteAt(layout, _scale, math.max(0, top));
    if (minute == null) return null;
    return WeekSlot(_dropDay(box, drag, pointer), snapToGrid(minute));
  }

  WeekSlot? _bandSlot(_Drag drag, Offset pointer) {
    final box = _bandKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return null;
    return WeekSlot(_dropDay(box, drag, pointer));
  }

  // --- Dragging ---------------------------------------------------------------------

  void _startDrag(Occurrence occurrence) {
    _hoverTimer?.cancel();
    setState(() => _drag = _Drag(occurrence, _pointerDown, _pointerDownGlobal));
    // A long press on touch opens the card; moving on makes it a drag.
    if (ItemDraggable.touch) _showCard(occurrence, pinned: false);
  }

  void _dragUpdate(DragUpdateDetails details) {
    final drag = _drag;
    if (drag == null || drag.moved) return;
    if ((details.globalPosition - drag.origin).distance > kTouchSlop) {
      drag.moved = true;
      _removeCard();
    }
  }

  void _endDrag() {
    final drag = _drag;
    if (drag == null) return;
    // Held without moving: the card stays open until a tap elsewhere.
    if (ItemDraggable.touch && !drag.moved) {
      _showCard(drag.occurrence, pinned: true);
    }
    if (mounted) setState(() => _drag = null);
  }

  void _hover(WeekSlot? slot) {
    final drag = _drag;
    if (drag == null || drag.slot == slot) return;
    setState(() => drag.slot = slot);
  }

  void _drop(Occurrence occurrence, WeekSlot? slot) {
    if (slot == null) return;
    widget.onMove?.call(occurrence, slot);
  }

  // --- The card ---------------------------------------------------------------------

  /// The rectangle of the event's block or bar, globally — where the card goes.
  Rect? _rectOf(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  BuildContext? _anchor;

  void _hoverEnter(BuildContext context, Occurrence occurrence) {
    if (widget.preview == null || _drag != null) return;
    _hideTimer?.cancel();
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || !context.mounted) return;
      _anchor = context;
      _showCard(occurrence, pinned: false);
    });
  }

  void _hoverExit() {
    _hoverTimer?.cancel();
    // A moment to reach the card itself.
    _hideTimer = Timer(const Duration(milliseconds: 200), _hideCard);
  }

  void _showCard(Occurrence occurrence, {required bool pinned}) {
    final builder = widget.preview;
    final anchor = _anchor;
    if (builder == null || anchor == null || !anchor.mounted) return;
    final global = _rectOf(anchor);
    if (global == null) return;
    _removeCard();
    final overlay = Overlay.of(context);
    // The card is positioned in the overlay's own coordinates, and on a wide screen the
    // overlay does not start at the window's corner (the navigation sits beside it) and
    // is narrower than the window: measured against the window, a card on Sunday — the
    // last column — ended behind the overlay's right edge.
    final overlayBox = overlay.context.findRenderObject();
    if (overlayBox is! RenderBox || !overlayBox.attached) return;
    final rect = global.shift(-overlayBox.localToGlobal(Offset.zero));
    final bounds = overlayBox.size;
    final entry = OverlayEntry(
      builder: (context) => _PreviewCard(
        key: _cardKey,
        rect: rect,
        bounds: bounds,
        occurrence: occurrence,
        colorToken: widget.calendars[occurrence.event.calendarId]?.colorToken,
        pinned: pinned,
        onDismiss: _hideCard,
        onEnter: () => _hideTimer?.cancel(),
        onExit: _hoverExit,
        onClosed: _removeCard,
        child: builder(context, occurrence),
      ),
    );
    overlay.insert(entry);
    _card = entry;
  }

  /// The card shrinks back into its event, then goes.
  void _hideCard() {
    _hideTimer?.cancel();
    final card = _cardKey.currentState;
    if (card == null) {
      _removeCard();
    } else {
      card.close();
    }
  }

  /// The card gone at once — a drag starts, the week goes.
  void _removeCard() {
    _card
      ?..remove()
      ..dispose();
    _card = null;
  }

  void _hoverBand(Offset pointer) {
    final drag = _drag;
    _hover(drag == null ? null : _bandSlot(drag, pointer));
  }

  void _dropOnBand(Occurrence occurrence, Offset pointer) {
    final drag = _drag;
    _drop(occurrence, drag == null ? null : _bandSlot(drag, pointer));
  }

  void _hoverHours(Offset pointer) {
    final drag = _drag;
    _hover(drag == null ? null : _hoursSlot(drag, pointer));
  }

  void _dropOnHours(Occurrence occurrence, Offset pointer) {
    final drag = _drag;
    _drop(occurrence, drag == null ? null : _hoursSlot(drag, pointer));
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final locale = Localizations.localeOf(context).toString();
    final days = widget.days;
    final kiosk = widget.kiosk;
    final height = widget.height;
    final layout = WeekLayout.of(
      days,
      widget.occurrences,
      always: _interactive ? widget.alwaysShown : null,
    );
    final today = startOfDay(_now);
    final first = startOfDay(days.first);
    final last = startOfDay(days.last);

    final spans = widget.occurrences
        .where(
          (item) =>
              item.isPinned &&
              !startOfDay(item.end).isBefore(first) &&
              !startOfDay(item.start).isAfter(last),
        )
        .toList();
    final lanes = assignSpanLanes(spans, from: first, to: last);
    final usedLanes = lanes.values.fold(
      0,
      (most, lane) => math.max(most, lane + 1),
    );
    // Where things can be dropped, the band is there even when empty: a timed event
    // dragged into it becomes an all-day one.
    final laneCount = _interactive ? math.max(1, usedLanes) : usedLanes;

    final skips = math.max(0, layout.segments.length - 1);
    final available =
        (height ?? 0) -
        _headerHeight -
        laneCount * (WeekTimeline._barHeight + HiwiskiMetrics.space2);
    final scale = switch (height) {
      _ when layout.shownMinutes == 0 => 0.0,
      null => 0.8,
      _ =>
        ((available - skips * WeekTimeline._skipHeight) / layout.shownMinutes)
            .clamp(WeekTimeline._minScale, WeekTimeline._maxScale),
    };
    _layout = layout;
    _scale = scale;

    return LayoutBuilder(
      builder: (context, constraints) {
        final column =
            (constraints.maxWidth - WeekTimeline._gutter) / days.length;
        _column = column;
        final drag = _drag;
        final bandSlot = drag?.slot?.allDay ?? false ? drag?.slot : null;
        final slot = drag?.slot;
        final hours = _Hours(
          key: _hoursKey,
          timeline: this,
          layout: layout,
          scale: scale,
          column: column,
          today: days.indexWhere((day) => startOfDay(day) == today),
          now: _now,
          calendars: widget.calendars,
          kiosk: widget.kiosk,
          locale: locale,
          target: (drag != null && slot != null && !slot.allDay)
              ? movedTime(drag.occurrence, slot)
              : null,
          onTap: widget.onSlotTap == null || widget.kiosk
              ? null
              : (local) {
                  final minute = _minuteAt(layout, scale, local.dy);
                  if (minute == null) return;
                  final index = ((local.dx - WeekTimeline._gutter) / column)
                      .floor();
                  if (index < 0 || index >= widget.days.length) return;
                  widget.onSlotTap?.call(
                    WeekSlot(
                      startOfDay(widget.days[index]),
                      snapToGrid(minute),
                    ),
                  );
                },
        );

        final band = SizedBox(
          key: _bandKey,
          height:
              laneCount * (WeekTimeline._barHeight + HiwiskiMetrics.space2) +
              HiwiskiMetrics.space2,
          child: Stack(
            children: [
              if ((drag, bandSlot) case (final drag?, final slot?))
                _BandTarget(
                  days: days,
                  column: column,
                  moved: movedTime(drag.occurrence, slot),
                ),
              for (final MapEntry(key: span, value: lane) in lanes.entries)
                _AllDayBar(
                  timeline: this,
                  kiosk: kiosk,
                  calendars: widget.calendars,
                  days: days,
                  span: span,
                  lane: lane,
                  column: column,
                  first: first,
                  last: last,
                ),
            ],
          ),
        );
        return Column(
          crossAxisAlignment: .stretch,
          children: [
            _Header(
              days: days,
              column: column,
              today: today,
              selected: widget.selected,
              locale: locale,
              onDayTap: kiosk ? null : widget.onDayTap,
            ),
            if (laneCount > 0)
              _interactive
                  ? DragTarget<Occurrence>(
                      onMove: (details) => _hoverBand(details.offset),
                      onLeave: (_) => _hover(null),
                      onAcceptWithDetails: (details) =>
                          _dropOnBand(details.data, details.offset),
                      builder: (context, _, _) => band,
                    )
                  : band,
            if (layout.segments.isEmpty)
              Padding(
                padding: const .symmetric(vertical: HiwiskiMetrics.space12),
                child: Text(
                  l.calWeekNoTimed,
                  textAlign: .center,
                  style: context.texts.bodySmall?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              _interactive
                  ? DragTarget<Occurrence>(
                      onMove: (details) => _hoverHours(details.offset),
                      onLeave: (_) => _hover(null),
                      onAcceptWithDetails: (details) =>
                          _dropOnHours(details.data, details.offset),
                      builder: (context, _, _) => hours,
                    )
                  : hours,
          ],
        );
      },
    );
  }

  double get _headerHeight => widget.kiosk
      ? HiwiskiMetrics.weekHeaderHeightKiosk
      : HiwiskiMetrics.weekHeaderHeight;
}

/// The minute of the day at [y] in the hours, or `null` in a skipped stretch.
int? _minuteAt(WeekLayout layout, double scale, double y) {
  if (scale <= 0) return null;
  double offset = 0.0;
  for (final segment in layout.segments) {
    final length = segment.length * scale;
    if (y >= offset && y <= offset + length) {
      return (segment.start + (y - offset) / scale).floor();
    }
    offset += length + WeekTimeline._skipHeight;
  }
  return null;
}

/// Where a dragged event would land in the all-day band: its days, faintly.
class _BandTarget extends StatelessWidget {
  const _BandTarget({
    required this.days,
    required this.column,
    required this.moved,
  });

  final List<DateTime> days;
  final double column;
  final ({DateTime start, DateTime end, bool allDay}) moved;

  @override
  Widget build(BuildContext context) {
    final from = days.indexWhere(
      (day) => startOfDay(day) == startOfDay(moved.start),
    );
    final until = days.indexWhere(
      (day) => startOfDay(day) == startOfDay(moved.end),
    );
    final start = from < 0 ? 0 : from;
    final end = until < 0 ? days.length - 1 : until;
    return Positioned(
      left: WeekTimeline._gutter + start * column,
      width: (end - start + 1) * column,
      top: 0,
      bottom: 0,
      child: const _TargetBox(label: null),
    );
  }
}

/// The outline where something dragged would land.
class _TargetBox extends StatelessWidget {
  const _TargetBox({required this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusEvent)),
        border: .fromBorderSide(
          BorderSide(color: scheme.primary, width: HiwiskiMetrics.strokeBold),
        ),
      ),
      child: switch (label) {
        null => const SizedBox.expand(),
        final label => Padding(
          padding: const .symmetric(horizontal: HiwiskiMetrics.space2),
          child: Text(
            label,
            maxLines: 1,
            overflow: .clip,
            style: context.texts.labelSmall?.copyWith(
              color: scheme.primary,
              fontWeight: .w600,
            ),
          ),
        ),
      },
    );
  }
}

/// An event's block or bar as the week view offers it: picked up to move, and opened
/// as a card on hover. Plain where the week is only read.
class _Movable extends StatelessWidget {
  const _Movable({
    required this.timeline,
    required this.occurrence,
    required this.feedback,
    required this.child,
  });

  final _WeekTimelineState timeline;
  final Occurrence occurrence;

  /// What follows the pointer, at the size of the block.
  final Widget feedback;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final interactive = !timeline.widget.kiosk;
    final preview = interactive && timeline.widget.preview != null;
    Widget result = child;
    if (timeline._mayMove(occurrence)) {
      result = ItemDraggable<Occurrence>(
        data: occurrence,
        // Built when the drag starts — by then the pointer has gone down, and the
        // block hangs from where it was taken hold of.
        feedback: Builder(
          builder: (context) => Material(
            type: .transparency,
            child: Transform.translate(
              offset: -timeline._pointerDown,
              child: Opacity(opacity: 0.85, child: feedback),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: child),
        onDragStarted: () => timeline._startDrag(occurrence),
        onDragUpdate: timeline._dragUpdate,
        onDragDone: timeline._endDrag,
        // The long press opens the card; it needs the drag from there on.
        liftsOnHold: true,
        child: child,
      );
    } else if (preview && ItemDraggable.touch) {
      // Nothing to move — a long press still opens the card.
      result = GestureDetector(
        onLongPress: () => timeline._showCard(occurrence, pinned: true),
        child: result,
      );
    }
    if (!interactive) return result;
    result = Listener(
      onPointerDown: (event) {
        timeline._pointerDown = event.localPosition;
        timeline._pointerDownGlobal = event.position;
        timeline._anchor = context;
        // A press on the event opens or moves it: the hover card steps aside.
        if (!ItemDraggable.touch) timeline._hideCard();
      },
      child: result,
    );
    if (preview) {
      result = MouseRegion(
        onEnter: (_) => timeline._hoverEnter(context, occurrence),
        onExit: (_) => timeline._hoverExit(),
        child: result,
      );
    }
    return result;
  }
}

/// The card an event opens into — **the event itself grows into it**: the card starts
/// exactly on the block, in its tint and with its title, and expands in place to the
/// card, the title growing with it as in a hero transition and the details fading in
/// below. Closing runs the same way back. Pinned — after a long press — it stays until
/// a tap elsewhere.
class _PreviewCard extends StatefulWidget {
  const _PreviewCard({
    super.key,
    required this.rect,
    required this.bounds,
    required this.occurrence,
    required this.colorToken,
    required this.pinned,
    required this.onDismiss,
    required this.onEnter,
    required this.onExit,
    required this.onClosed,
    required this.child,
  });

  /// The block or bar it grows out of, in the overlay's coordinates.
  final Rect rect;

  /// The overlay's size — what the card has to stay within.
  final Size bounds;
  final Occurrence occurrence;
  final String? colorToken;
  final bool pinned;
  final VoidCallback onDismiss;
  final VoidCallback onEnter;
  final VoidCallback onExit;

  /// Shrunk back into the block: the entry can go.
  final VoidCallback onClosed;

  /// What the card shows below the title.
  final Widget child;

  @override
  State<_PreviewCard> createState() => _PreviewCardState();
}

class _PreviewCardState extends State<_PreviewCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 180),
  )..forward();

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  /// Back into the block, then gone. A reverse interrupted — the pointer came back —
  /// never completes, so the card stays.
  void close() =>
      // A ticker future only errors when its ticker is disposed — the card is gone
      // then anyway.
      _grow.reverse().whenComplete(widget.onClosed).ignore();

  void _enter() {
    _grow.forward();
    widget.onEnter();
  }

  @override
  Widget build(BuildContext context) {
    final rect = widget.rect;
    final screen = widget.bounds;
    const gap = HiwiskiMetrics.space8;
    final width = math.min(
      HiwiskiMetrics.weekPreviewWidth,
      screen.width - 2 * gap,
    );
    final maxHeight = math.min(
      HiwiskiMetrics.weekPreviewMaxHeight,
      screen.height - 2 * gap,
    );
    // It grows from where the block is, kept on the screen.
    final endLeft = rect.left
        .clamp(gap, math.max(gap, screen.width - width - gap))
        .toDouble();
    final endTop = rect.top
        .clamp(gap, math.max(gap, screen.height - maxHeight - gap))
        .toDouble();
    final colorToken = widget.colorToken ?? ColorTokens.blue;
    final tint = context.tokens.tags[tintOf(colorToken)]!;
    final accent = context.tokens.accent(accentOf(colorToken));
    final scheme = context.scheme;
    final small = context.texts.labelSmall?.copyWith(
      color: tint.foreground,
      fontWeight: .w600,
      height: HiwiskiMetrics.lineHeightTight,
    );
    final large = context.texts.titleMedium?.copyWith(
      color: scheme.onSurface,
      fontWeight: .w600,
    );

    final card = AnimatedBuilder(
      animation: _grow,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_grow.value);
        double lerp(double a, double b) => a + (b - a) * t;
        final padding = EdgeInsets.lerp(
          const .symmetric(
            horizontal: HiwiskiMetrics.space2,
            vertical: HiwiskiMetrics.hairline,
          ),
          const .all(HiwiskiMetrics.space16),
          t,
        );
        final radius = lerp(
          HiwiskiMetrics.radiusEvent,
          HiwiskiMetrics.radiusCard,
        );
        return Positioned(
          left: lerp(rect.left, endLeft),
          top: lerp(rect.top, endTop),
          width: lerp(rect.width, width),
          child: MouseRegion(
            onEnter: (_) => _enter(),
            onExit: (_) => widget.onExit(),
            child: Material(
              elevation: lerp(0, HiwiskiMetrics.elevationMenu),
              color: Color.lerp(
                tint.background,
                scheme.surfaceContainerHigh,
                t,
              ),
              borderRadius: .all(.circular(radius)),
              clipBehavior: .antiAlias,
              child: ConstrainedBox(
                // Exactly the block at the start; at the end as tall as it needs.
                constraints: BoxConstraints(
                  minHeight: lerp(rect.height, 0),
                  maxHeight: lerp(rect.height, maxHeight),
                ),
                // A stack and not a stretched row: the row took the whole maximum
                // height, and a short event's card stood half empty.
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      physics: t < 1
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      padding: padding?.add(
                        const .only(left: HiwiskiMetrics.calendarStripeWidth),
                      ),
                      child: Column(
                        crossAxisAlignment: .stretch,
                        mainAxisSize: .min,
                        children: [
                          Text(
                            widget.occurrence.event.title,
                            maxLines: t < 0.5 ? 1 : 3,
                            overflow: .ellipsis,
                            style: TextStyle.lerp(small, large, t),
                          ),
                          // The details come once there is room for them.
                          Opacity(
                            opacity: ((t - 0.4) / 0.6).clamp(0.0, 1.0),
                            child: Padding(
                              padding: .only(
                                top: lerp(0, HiwiskiMetrics.space12),
                              ),
                              child: widget.child,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // The calendar's stripe stays: it is the same event.
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: HiwiskiMetrics.calendarStripeWidth,
                      child: ColoredBox(color: accent),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    return Stack(
      children: [
        if (widget.pinned)
          Positioned.fill(
            child: GestureDetector(
              behavior: .opaque,
              onTap: widget.onDismiss,
              child: const SizedBox.expand(),
            ),
          ),
        card,
      ],
    );
  }
}

int _indexIn(List<DateTime> days, DateTime day) =>
    days.indexWhere((candidate) => startOfDay(candidate) == day);

class _AllDayBar extends StatelessWidget {
  const _AllDayBar({
    required this.timeline,
    required this.kiosk,
    required this.calendars,
    required this.days,
    required this.span,
    required this.lane,
    required this.column,
    required this.first,
    required this.last,
  });

  final _WeekTimelineState timeline;
  final bool kiosk;
  final Map<String, Calendar> calendars;
  final List<DateTime> days;
  final Occurrence span;
  final int lane;
  final double column;
  final DateTime first;
  final DateTime last;

  @override
  Widget build(BuildContext context) {
    final start = startOfDay(span.start);
    final end = startOfDay(span.end);
    final from = start.isBefore(first) ? 0 : _indexIn(days, start);
    final to = end.isAfter(last) ? days.length - 1 : _indexIn(days, end);
    final tint =
        context.tokens.tags[tintOf(
          calendars[span.event.calendarId]?.colorToken ?? ColorTokens.blue,
        )]!;
    // Square where it goes on beyond the week shown, round where it begins and ends.
    final radius = BorderRadius.horizontal(
      left: .circular(start.isBefore(first) ? 0 : HiwiskiMetrics.radiusEvent),
      right: .circular(end.isAfter(last) ? 0 : HiwiskiMetrics.radiusEvent),
    );
    final bar = Material(
      color: tint.background,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: kiosk ? null : () => openOccurrence(context, span),
        child: Padding(
          padding: const .symmetric(horizontal: HiwiskiMetrics.space4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              span.event.title,
              maxLines: 1,
              overflow: .clip,
              softWrap: false,
              style: context.texts.labelSmall?.copyWith(
                color: tint.foreground,
                fontWeight: .w600,
              ),
            ),
          ),
        ),
      ),
    );
    return Positioned(
      left: WeekTimeline._gutter + from * column + HiwiskiMetrics.hairline,
      width: (to - from + 1) * column - 2 * HiwiskiMetrics.hairline,
      top:
          lane * (WeekTimeline._barHeight + HiwiskiMetrics.space2) +
          HiwiskiMetrics.hairline,
      height: WeekTimeline._barHeight,
      child: _Movable(
        timeline: timeline,
        occurrence: span,
        feedback: SizedBox(
          width: (to - from + 1) * column - 2 * HiwiskiMetrics.hairline,
          height: WeekTimeline._barHeight,
          child: bar,
        ),
        child: bar,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.days,
    required this.column,
    required this.today,
    required this.selected,
    required this.locale,
    required this.onDayTap,
  });

  final List<DateTime> days;
  final double column;
  final DateTime today;
  final DateTime? selected;
  final String locale;
  final ValueChanged<DateTime>? onDayTap;

  @override
  Widget build(BuildContext context) {
    final weekday = DateFormat.E(locale);
    return Row(
      children: [
        const SizedBox(width: WeekTimeline._gutter),
        for (final day in days)
          SizedBox(
            width: column,
            child: InkWell(
              onTap: switch (onDayTap) {
                null => null,
                final onDayTap => () => onDayTap(day),
              },
              borderRadius: const .all(.circular(HiwiskiMetrics.radiusMenu)),
              child: Padding(
                padding: const .symmetric(vertical: HiwiskiMetrics.space2),
                child: Column(
                  children: [
                    Text(
                      weekday.format(day),
                      maxLines: 1,
                      overflow: .clip,
                      style: context.texts.labelSmall?.copyWith(
                        color: day.weekday >= DateTime.saturday
                            ? context.scheme.primary
                            : context.scheme.onSurfaceVariant,
                      ),
                    ),
                    Container(
                      width: HiwiskiMetrics.dayCircleCompact,
                      height: HiwiskiMetrics.dayCircleCompact,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: .circle,
                        // Today filled, the chosen day ringed — as in the month.
                        color: startOfDay(day) == today
                            ? context.scheme.primary
                            : null,
                        border:
                            startOfDay(day) == selected &&
                                startOfDay(day) != today
                            ? Border.fromBorderSide(
                                BorderSide(color: context.scheme.primary),
                              )
                            : null,
                      ),
                      child: Text(
                        '${day.day}',
                        style: context.texts.labelMedium?.copyWith(
                          fontWeight: .w600,
                          color: startOfDay(day) == today
                              ? context.scheme.onPrimary
                              : context.scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The shown hours: hour lines, the skips between stretches, the blocks.
/// Where a minute of the day sits, or `null` in a skipped stretch.
double? _yOf(WeekLayout layout, double scale, int minute) {
  double offset = 0.0;
  for (final segment in layout.segments) {
    if (minute >= segment.start && minute <= segment.end) {
      return offset + (minute - segment.start) * scale;
    }
    offset += segment.length * scale + WeekTimeline._skipHeight;
  }
  return null;
}

class _Hours extends StatelessWidget {
  const _Hours({
    super.key,
    required this.timeline,
    required this.target,
    required this.onTap,
    required this.layout,
    required this.scale,
    required this.column,
    required this.today,
    required this.now,
    required this.calendars,
    required this.kiosk,
    required this.locale,
  });

  final _WeekTimelineState timeline;

  /// Where something dragged would land, if over the hours.
  final ({DateTime start, DateTime end, bool allDay})? target;

  /// A tap into free hours, at its local position.
  final ValueChanged<Offset>? onTap;

  final WeekLayout layout;
  final double scale;
  final double column;

  /// The column of today, or -1.
  final int today;

  /// Where the now line stands in today's column.
  final DateTime now;
  final Map<String, Calendar> calendars;
  final bool kiosk;
  final String locale;

  double? _y(int minute) => _yOf(layout, scale, minute);

  /// The outline of a drop target in the hours: its day's column, from its start for
  /// its length.
  Rect? _targetRect(({DateTime start, DateTime end, bool allDay}) target) {
    final day = layout.days.indexWhere(
      (candidate) => startOfDay(candidate) == startOfDay(target.start),
    );
    final top = _y(target.start.hour * 60 + target.start.minute);
    if (day < 0 || top == null) return null;
    final minutes = math.max(
      WeekLayout.minLength,
      target.end.difference(target.start).inMinutes,
    );
    final bottom =
        _y(target.start.hour * 60 + target.start.minute + minutes) ??
        top + minutes * scale;
    return Rect.fromLTWH(
      WeekTimeline._gutter + day * column + HiwiskiMetrics.hairline,
      top,
      column - 2 * HiwiskiMetrics.hairline,
      math.max(bottom - top, WeekTimeline._barHeight),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final segments = layout.segments;
    final total =
        layout.shownMinutes * scale +
        (segments.length - 1) * WeekTimeline._skipHeight;
    final muted = context.scheme.onSurfaceVariant;
    // Every hour where they have room, every second one where they would crowd.
    final labelEvery = scale * 60 < 22 ? 120 : 60;

    final nowY = today < 0 ? null : _y(now.hour * 60 + now.minute);

    double offset = 0.0;
    final skipTops = <(double, TimeSegment, TimeSegment)>[];
    for (int i = 0; i < segments.length; i++) {
      offset += segments[i].length * scale;
      if (i < segments.length - 1) {
        skipTops.add((offset, segments[i], segments[i + 1]));
        offset += WeekTimeline._skipHeight;
      }
    }

    String hour(int minute) =>
        DateFormat.Hm(locale)
            .format(DateTime(2000, 1, 1, minute ~/ 60, minute % 60));

    return SizedBox(
      height: total + HiwiskiMetrics.space8,
      child: Stack(
        clipBehavior: .none,
        children: [
          // Today's column, faintly.
          if (today >= 0)
            Positioned(
              left: WeekTimeline._gutter + today * column,
              width: column,
              top: 0,
              height: total,
              child: ColoredBox(
                color: context.scheme.primary.withValues(alpha: 0.06),
              ),
            ),
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(
                lines: [
                  for (final segment in segments)
                    for (
                      var minute = segment.start;
                      minute <= segment.end;
                      minute += 60
                    )
                      ?_y(minute),
                ],
                skips: [for (final skip in skipTops) skip.$1],
                gutter: WeekTimeline._gutter,
                columns: layout.days.length,
                column: column,
                line: context.tokens.divider,
                wave: muted,
              ),
            ),
          ),
          for (final segment in segments)
            for (
              var minute = segment.start;
              minute <= segment.end;
              minute += labelEvery
            )
              if (_y(minute) case final y?)
                Positioned(
                  left: 0,
                  width: WeekTimeline._gutter - HiwiskiMetrics.space4,
                  top: y - HiwiskiMetrics.space8,
                  child: Text(
                    hour(minute),
                    textAlign: .right,
                    style: context.texts.labelSmall?.copyWith(color: muted),
                  ),
                ),
          // The skip, said in words for a screen reader; the wave says it for the eye.
          for (final (top, before, after) in skipTops)
            Positioned(
              left: 0,
              right: 0,
              top: top,
              height: WeekTimeline._skipHeight,
              child: Semantics(
                label: l.calWeekSkipped(hour(before.end), hour(after.start)),
                child: const SizedBox.expand(),
              ),
            ),
          // Free hours take a tap: below the blocks, which take their own.
          if (onTap case final onTap?)
            Positioned.fill(
              child: GestureDetector(
                behavior: .translucent,
                onTapUp: (details) => onTap(details.localPosition),
              ),
            ),
          if (target case final target?)
            if (_targetRect(target) case final rect?)
              Positioned.fromRect(
                rect: rect,
                child: _TargetBox(
                  label: DateFormat.Hm(locale).format(target.start),
                ),
              ),
          for (final day in layout.pieces)
            for (final piece in day)
              _DayBlock(
                timeline: timeline,
                locale: locale,
                kiosk: kiosk,
                calendars: calendars,
                column: column,
                layout: layout,
                scale: scale,
                piece: piece,
              ),
          if (nowY != null)
            Positioned(
              left:
                  WeekTimeline._gutter +
                  today * column -
                  HiwiskiMetrics.dotTiny / 2,
              width: column + HiwiskiMetrics.dotTiny / 2,
              top: nowY - HiwiskiMetrics.dotTiny / 2,
              height: HiwiskiMetrics.dotTiny,
              child: _NowLine(color: context.scheme.error),
            ),
        ],
      ),
    );
  }
}

class _DayBlock extends StatelessWidget {
  const _DayBlock({
    required this.timeline,
    required this.locale,
    required this.kiosk,
    required this.calendars,
    required this.column,
    required this.layout,
    required this.scale,
    required this.piece,
  });

  final _WeekTimelineState timeline;
  final String locale;
  final bool kiosk;
  final Map<String, Calendar> calendars;
  final double column;
  final WeekLayout layout;
  final double scale;
  final DayPiece piece;

  @override
  Widget build(BuildContext context) {
    // A piece starts inside a shown stretch: the layout skips only empty ones.
    final top = _yOf(layout, scale, piece.start) ?? 0;
    final bottom =
        _yOf(layout, scale, piece.end) ?? top + WeekLayout.minLength * scale;
    final width = column / piece.columns;
    final calendar = calendars[piece.occurrence.event.calendarId];
    final tint =
        context.tokens.tags[tintOf(calendar?.colorToken ?? ColorTokens.blue)]!;
    final accent = context.tokens.accent(
      accentOf(calendar?.colorToken ?? ColorTokens.blue),
    );
    final height = math.max(bottom - top - 1, 12.0);
    final style = (kiosk ? context.texts.labelMedium : context.texts.labelSmall)
        ?.copyWith(
          color: tint.foreground,
          height: HiwiskiMetrics.lineHeightTight,
        );
    final time = DateFormat.Hm(locale).format(piece.occurrence.start);
    const shape = RoundedRectangleBorder(
      borderRadius: .all(.circular(HiwiskiMetrics.radiusEvent)),
    );

    // Rounded by its shape, not by a clip: an anti-aliased clip per event is a layer
    // of its own, and a week swiped by has dozens of them in every frame.
    final block = Material(
      color: tint.background,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: kiosk ? null : () => openOccurrence(context, piece.occurrence),
        child: Row(
          crossAxisAlignment: .stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: accent,
                // The context is BorderRadiusGeometry: abstract, a shorthand finds no constructor.
                // ignore: many_lints/prefer_shorthands_with_constructors
                borderRadius: const BorderRadius.horizontal(
                  left: .circular(HiwiskiMetrics.radiusEvent),
                ),
              ),
              child: const SizedBox(width: HiwiskiMetrics.calendarStripeWidth),
            ),
            Expanded(
              child: Padding(
                padding: const .symmetric(
                  horizontal: HiwiskiMetrics.space2,
                  vertical: HiwiskiMetrics.hairline,
                ),
                child: Semantics(
                  label: '$time ${piece.occurrence.event.title}',
                  excludeSemantics: true,
                  child: Text(
                    // The time only where there is room for it below the title.
                    height > 30 && width > 44
                        ? '${piece.occurrence.event.title}\n$time'
                        : piece.occurrence.event.title,
                    maxLines: math.max(1, (height - 2) ~/ 13),
                    overflow: .clip,
                    style: style,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Positioned(
      left:
          WeekTimeline._gutter +
          piece.day * column +
          piece.column * width +
          HiwiskiMetrics.hairline,
      width: width - 2 * HiwiskiMetrics.hairline,
      top: top + HiwiskiMetrics.hairline / 2,
      height: height,
      child: _Movable(
        timeline: timeline,
        occurrence: piece.occurrence,
        // Held, it takes its day's whole width — side by side it may be narrow.
        feedback: SizedBox(
          width: column - 2 * HiwiskiMetrics.hairline,
          height: height,
          child: block,
        ),
        child: block,
      ),
    );
  }
}

class _NowLine extends StatelessWidget {
  const _NowLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: HiwiskiMetrics.dotTiny,
        height: HiwiskiMetrics.dotTiny,
        decoration: BoxDecoration(color: color, shape: .circle),
      ),
      Expanded(
        child: Container(height: HiwiskiMetrics.strokeBold, color: color),
      ),
    ],
  );
}

/// Hour lines across the days, thin day separators, and the wavy break where hours are
/// skipped — a vertical tilde in the time column, a wave across the days.
class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.lines,
    required this.skips,
    required this.gutter,
    required this.columns,
    required this.column,
    required this.line,
    required this.wave,
  });

  final List<double> lines;
  final List<double> skips;
  final double gutter;
  final int columns;
  final double column;
  final Color line;
  final Color wave;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (final y in lines) {
      canvas.drawLine(Offset(gutter, y), Offset(size.width, y), linePaint);
    }
    for (int i = 1; i < columns; i++) {
      final x = gutter + i * column;
      double top = 0.0;
      for (final skip in [...skips, size.height - 8]) {
        canvas.drawLine(Offset(x, top), Offset(x, skip), linePaint);
        top = skip + WeekTimeline._skipHeight;
      }
    }

    final wavePaint = Paint()
      ..color = wave.withValues(alpha: 0.6)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (final top in skips) {
      final middle = top + WeekTimeline._skipHeight / 2;
      // Across the days: a wave, as on a broken axis.
      final across = Path()..moveTo(gutter, middle);
      for (double x = gutter; x < size.width; x += 8) {
        across.relativeQuadraticBezierTo(2, -3, 4, 0);
        across.relativeQuadraticBezierTo(2, 3, 4, 0);
      }
      canvas.drawPath(across, wavePaint);
      // In the time column: the tilde standing upright.
      final x = gutter - 10;
      final upright = Path()
        ..moveTo(x, top + 2)
        ..cubicTo(
          x + 5,
          top + 6,
          x - 5,
          top + WeekTimeline._skipHeight - 6,
          x,
          top + WeekTimeline._skipHeight - 2,
        );
      canvas.drawPath(upright, wavePaint..strokeWidth = 1.6);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      !listEquals(old.lines, lines) ||
      !listEquals(old.skips, skips) ||
      old.gutter != gutter ||
      old.columns != columns ||
      old.column != column ||
      old.line != line ||
      old.wave != wave;
}
