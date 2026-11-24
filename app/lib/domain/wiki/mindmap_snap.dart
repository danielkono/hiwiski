/// Lining elements up on a mind map: what a moved or resized element snaps to, and
/// the commands that align, distribute and size a group — pure geometry on boxes in
/// the map's units, applied by the canvas and the ViewModel.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

/// A line something snapped to: vertical at x = [at] or horizontal at y = [at],
/// drawn [from] [to] along it — across everything that lines up there.
typedef SnapGuide = ({bool vertical, double at, double from, double to});

/// One of the equal gaps of a row: from [from] to [to] along the row, at [across]
/// — the middle of the two boxes it lies between, the other way.
typedef SnapGap = ({bool horizontal, double from, double to, double across});

/// What a move snapped to: how far to shift the box, and the guides and the equal
/// gaps to show.
typedef SnapMove = ({Offset by, List<SnapGuide> guides, List<SnapGap> gaps});

/// What a resize snapped to: the size, the guides, and the boxes whose width or
/// height it took.
typedef SnapResize = ({Size size, List<SnapGuide> guides, List<Rect> matched});

/// Where [moving] snaps among [others]: on each axis on its own, to the nearest
/// line of another box — its start, middle or end — or to a gap that already lies
/// between two neighbours in the same row, within [reach]. Without either, to the
/// [grid] where one is given.
SnapMove snapMove(
  Rect moving,
  List<Rect> others, {
  required double reach,
  double? grid,
}) {
  final x = _snapAxis(moving, others, reach: reach, grid: grid, across: true);
  final y = _snapAxis(moving, others, reach: reach, grid: grid, across: false);
  final placed = moving.shift(Offset(x.delta, y.delta));
  return (
    by: Offset(x.delta, y.delta),
    guides: [
      if (x.line case final at?) _guide(placed, others, at, vertical: true),
      if (y.line case final at?) _guide(placed, others, at, vertical: false),
    ],
    gaps: [
      if (x.gap case final gap?)
        ..._gapsOf(placed, others, gap, horizontal: true),
      if (y.gap case final gap?)
        ..._gapsOf(placed, others, gap, horizontal: false),
    ],
  );
}

/// Where a box at [box] being resized by its bottom right corner snaps: its right
/// and bottom edges to the lines of [others], its width and height to theirs, within
/// [reach]; otherwise to the [grid] where one is given. With [aspect] — a picture,
/// a member's circle — the side that moved less follows the other.
SnapResize snapResize(
  Rect box,
  List<Rect> others, {
  required double reach,
  double? grid,
  double? aspect,
  double minimum = 1,
}) {
  final width = _snapSide(box, others, reach: reach, grid: grid, across: true);
  final height = _snapSide(
    box,
    others,
    reach: reach,
    grid: grid,
    across: false,
  );
  double w = box.width + width.delta;
  double h = box.height + height.delta;
  bool useWidth = true;
  bool useHeight = true;
  if (aspect != null && aspect > 0) {
    // One side decides, the other follows the shape: the one that snapped — or,
    // both having snapped, the one that moved less to do it.
    useWidth =
        width.snapped &&
        (!height.snapped || width.delta.abs() <= height.delta.abs());
    useHeight = !useWidth && height.snapped;
    if (useWidth) {
      h = w / aspect;
    } else if (useHeight) {
      w = h * aspect;
    } else {
      w = box.width;
      h = box.height;
    }
    // Grown as a whole where a side fell below [minimum]: each side raised on its
    // own, a picture snapped small was stretched out of its shape. It then no
    // longer meets what it snapped to, and no guide says it does.
    if (w < minimum || h < minimum) {
      // A side snapped to no length at all has no shape to grow: as it was.
      final grow = w > 0 && h > 0 ? math.max(minimum / w, minimum / h) : null;
      w = grow == null ? box.width : w * grow;
      h = grow == null ? box.height : h * grow;
      useWidth = false;
      useHeight = false;
    }
  }
  w = math.max(minimum, w);
  h = math.max(minimum, h);
  final sized = Rect.fromLTWH(box.left, box.top, w, h);
  return (
    size: Size(w, h),
    guides: [
      if (useWidth)
        if (width.line case final at?)
          _guide(sized, others, at, vertical: true),
      if (useHeight)
        if (height.line case final at?)
          _guide(sized, others, at, vertical: false),
    ],
    matched: [if (useWidth) ...width.matched, if (useHeight) ...height.matched],
  );
}

/// The nearest multiple of [grid] to [value].
double snapToGrid(double value, double grid) =>
    grid <= 0 ? value : (value / grid).roundToDouble() * grid;

// --- Moving ------------------------------------------------------------------------

typedef _Axis = ({double delta, double? line, double? gap});

/// The start, middle and end of [box] along x ([across]) or y.
List<double> _lines(Rect box, {required bool across}) => across
    ? [box.left, box.center.dx, box.right]
    : [box.top, box.center.dy, box.bottom];

double _start(Rect box, {required bool across}) => across ? box.left : box.top;
double _end(Rect box, {required bool across}) =>
    across ? box.right : box.bottom;

/// Whether [a] and [b] lie in one row along x ([across]): they overlap the other way.
bool _inRow(Rect a, Rect b, {required bool across}) => across
    ? a.top < b.bottom && b.top < a.bottom
    : a.left < b.right && b.left < a.right;

_Axis _snapAxis(
  Rect moving,
  List<Rect> others, {
  required double reach,
  required double? grid,
  required bool across,
}) {
  double? best;
  double? line;
  double? gap;
  void consider(double delta, {double? toLine, double? toGap}) {
    if (delta.abs() > reach) return;
    if (best case final held? when delta.abs() >= held.abs()) return;
    best = delta;
    line = toLine;
    gap = toGap;
  }

  final own = _lines(moving, across: across);
  for (final other in others) {
    for (final target in _lines(other, across: across)) {
      for (final mine in own) {
        consider(target - mine, toLine: target);
      }
    }
  }
  // An equal gap: after the neighbour before it, before the one after it, or
  // halfway between the two — each as wide as a gap already in the row.
  final row =
      [
        for (final other in others)
          if (_inRow(moving, other, across: across)) other,
      ]..sort(
        (a, b) =>
            _start(a, across: across).compareTo(_start(b, across: across)),
      );
  final gaps = _gapsIn(row, across: across);
  final start = _start(moving, across: across);
  final end = _end(moving, across: across);
  final before = [
    for (final other in row)
      if (_end(other, across: across) <= start + reach) other,
  ].lastOrNull;
  final after = [
    for (final other in row)
      if (_start(other, across: across) >= end - reach) other,
  ].firstOrNull;
  for (final width in gaps) {
    if (before != null) {
      consider(_end(before, across: across) + width - start, toGap: width);
    }
    if (after != null) {
      consider(_start(after, across: across) - width - end, toGap: width);
    }
  }
  if (before != null && after != null) {
    final room =
        _start(after, across: across) -
        _end(before, across: across) -
        (end - start);
    if (room > 0) {
      consider(
        _end(before, across: across) + room / 2 - start,
        toGap: room / 2,
      );
    }
  }
  if (best case final delta?) return (delta: delta, line: line, gap: gap);
  // No element in reach: the grid, if there is one.
  if (grid != null && grid > 0) {
    return (delta: snapToGrid(start, grid) - start, line: null, gap: null);
  }
  return (delta: 0, line: null, gap: null);
}

/// The gaps between neighbours of [row] that do not overlap, each once, rounded to
/// whole units.
Set<double> _gapsIn(List<Rect> row, {required bool across}) => {
  for (int i = 1; i < row.length; i++)
    if (_start(row[i], across: across) - _end(row[i - 1], across: across)
        case final gap when gap > 0)
      gap.roundToDouble(),
};

SnapGuide _guide(
  Rect placed,
  List<Rect> others,
  double at, {
  required bool vertical,
}) {
  final along = [
    placed,
    for (final other in others)
      if (_lines(
        other,
        across: vertical,
      ).any((line) => (line - at).abs() < 0.5))
        other,
  ];
  return (
    vertical: vertical,
    at: at,
    from: along.map((box) => vertical ? box.top : box.left).reduce(math.min),
    to: along.map((box) => vertical ? box.bottom : box.right).reduce(math.max),
  );
}

/// Every gap of [width] in the row of [placed] — the one it now has and those it
/// matched.
List<SnapGap> _gapsOf(
  Rect placed,
  List<Rect> others,
  double width, {
  required bool horizontal,
}) {
  final row =
      [
        placed,
        for (final other in others)
          if (_inRow(placed, other, across: horizontal)) other,
      ]..sort(
        (a, b) => _start(
          a,
          across: horizontal,
        ).compareTo(_start(b, across: horizontal)),
      );
  return [
    for (int i = 1; i < row.length; i++)
      if (_start(row[i], across: horizontal) -
              _end(row[i - 1], across: horizontal)
          case final gap when (gap - width).abs() < 1)
        (
          horizontal: horizontal,
          from: _end(row[i - 1], across: horizontal),
          to: _start(row[i], across: horizontal),
          across: horizontal
              ? (row[i - 1].center.dy + row[i].center.dy) / 2
              : (row[i - 1].center.dx + row[i].center.dx) / 2,
        ),
  ];
}

// --- Resizing ----------------------------------------------------------------------

typedef _Side = ({
  double delta,
  double? line,
  bool snapped,
  List<Rect> matched,
});

_Side _snapSide(
  Rect box,
  List<Rect> others, {
  required double reach,
  required double? grid,
  required bool across,
}) {
  final edge = _end(box, across: across);
  final size = across ? box.width : box.height;
  double? best;
  double? line;
  List<Rect> matched = const [];
  for (final other in others) {
    for (final target in _lines(other, across: across)) {
      final delta = target - edge;
      if (delta.abs() <= reach && (best == null || delta.abs() < best.abs())) {
        best = delta;
        line = target;
        matched = const [];
      }
    }
  }
  // As wide or as high as another — that one is marked; it wins over a line only
  // when nearer.
  for (final other in others) {
    final delta = (across ? other.width : other.height) - size;
    if (delta.abs() <= reach && (best == null || delta.abs() < best.abs())) {
      best = delta;
      line = null;
    }
  }
  if (best case final delta?) {
    if (line == null) {
      matched = [
        for (final other in others)
          if (((across ? other.width : other.height) - (size + delta)).abs() <
              0.5)
            other,
      ];
    }
    return (delta: delta, line: line, snapped: true, matched: matched);
  }
  if (grid != null && grid > 0) {
    return (
      delta: snapToGrid(edge, grid) - edge,
      line: null,
      snapped: true,
      matched: const [],
    );
  }
  return (delta: 0, line: null, snapped: false, matched: const []);
}

// --- A group ------------------------------------------------------------------------

/// How a group is aligned: to its outermost edge on one side, or to its middle.
enum MindmapAlign { left, centre, right, top, middle, bottom }

/// [boxes] aligned as [align] says: each moved, none resized.
Map<K, Rect> alignBoxes<K>(Map<K, Rect> boxes, MindmapAlign align) {
  if (boxes.isEmpty) return boxes;
  final all = boxes.values.reduce((a, b) => a.expandToInclude(b));
  return {
    for (final MapEntry(:key, value: box) in boxes.entries)
      key: box.shift(switch (align) {
        .left => Offset(all.left - box.left, 0),
        .centre => Offset(all.center.dx - box.center.dx, 0),
        .right => Offset(all.right - box.right, 0),
        .top => Offset(0, all.top - box.top),
        .middle => Offset(0, all.center.dy - box.center.dy),
        .bottom => Offset(0, all.bottom - box.bottom),
      }),
  };
}

/// [boxes] spread evenly along x ([horizontal]) or y: the first and the last stay,
/// the gaps between neighbours become equal. Fewer than three stay as they are.
Map<K, Rect> distributeBoxes<K>(
  Map<K, Rect> boxes, {
  required bool horizontal,
}) {
  if (boxes.length < 3) return boxes;
  final sorted = boxes.entries.toList()
    ..sort(
      (a, b) => _start(
        a.value,
        across: horizontal,
      ).compareTo(_start(b.value, across: horizontal)),
    );
  final first = _start(sorted.first.value, across: horizontal);
  final last = sorted
      .map((entry) => _end(entry.value, across: horizontal))
      .reduce(math.max);
  final taken = sorted.fold<double>(
    0,
    (sum, entry) => sum + (horizontal ? entry.value.width : entry.value.height),
  );
  final gap = (last - first - taken) / (sorted.length - 1);
  final placed = <K, Rect>{};
  double at = first;
  for (final MapEntry(:key, value: box) in sorted) {
    placed[key] = horizontal
        ? Rect.fromLTWH(at, box.top, box.width, box.height)
        : Rect.fromLTWH(box.left, at, box.width, box.height);
    at += (horizontal ? box.width : box.height) + gap;
  }
  return placed;
}

/// [boxes] side by side ([horizontal]) or one below the other, [gap] apart: in the
/// order they stand that way — the first where it is — and lined up on the group's
/// middle the other way. Two that stand level go in reading order. None resized.
Map<K, Rect> lineUpBoxes<K>(
  Map<K, Rect> boxes, {
  required bool horizontal,
  required double gap,
}) {
  final all = boxes.values.fold<Rect?>(
    null,
    (all, box) => all?.expandToInclude(box) ?? box,
  );
  if (all == null) return boxes;
  final sorted = boxes.entries.toList()
    ..sort((a, b) {
      final along = _start(
        a.value,
        across: horizontal,
      ).compareTo(_start(b.value, across: horizontal));
      if (along != 0) return along;
      return _start(
        a.value,
        across: !horizontal,
      ).compareTo(_start(b.value, across: !horizontal));
    });
  final placed = <K, Rect>{};
  // The first where it stands: where the group begins that way.
  double at = _start(all, across: horizontal);
  for (final MapEntry(:key, value: box) in sorted) {
    placed[key] = horizontal
        ? Rect.fromLTWH(
            at,
            all.center.dy - box.height / 2,
            box.width,
            box.height,
          )
        : Rect.fromLTWH(
            all.center.dx - box.width / 2,
            at,
            box.width,
            box.height,
          );
    at += (horizontal ? box.width : box.height) + gap;
  }
  return placed;
}

/// [boxes] as wide ([width]) and/or as high ([height]) as the largest of them —
/// with both, the size of the one covering most. Those with an aspect in
/// [aspects] keep their shape: the side asked for decides, and with both the box
/// fits into the size. Each keeps its top left corner.
Map<K, Rect> sameSizeBoxes<K>(
  Map<K, Rect> boxes, {
  required bool width,
  required bool height,
  Map<K, double> aspects = const {},
}) {
  if (boxes.isEmpty || (!width && !height)) return boxes;
  final widest = boxes.values.map((box) => box.width).reduce(math.max);
  final highest = boxes.values.map((box) => box.height).reduce(math.max);
  final largest = boxes.values.reduce(
    (a, b) => a.width * a.height >= b.width * b.height ? a : b,
  );
  final target = switch ((width, height)) {
    (true, true) => largest.size,
    (true, false) => Size(widest, 0),
    _ => Size(0, highest),
  };
  return {
    for (final MapEntry(:key, value: box) in boxes.entries)
      key:
          box.topLeft &
          _sized(
            box.size,
            target,
            width: width,
            height: height,
            aspect: aspects[key],
          ),
  };
}

/// [size] made [target]'s width and/or height; with [aspect], keeping its shape.
Size _sized(
  Size size,
  Size target, {
  required bool width,
  required bool height,
  required double? aspect,
}) {
  if (aspect == null || aspect <= 0) {
    return Size(
      width ? target.width : size.width,
      height ? target.height : size.height,
    );
  }
  if (width && height) {
    // Fitted into the target, whole.
    return size *
        math.min(target.width / size.width, target.height / size.height);
  }
  return width
      ? Size(target.width, target.width / aspect)
      : Size(target.height * aspect, target.height);
}
