import 'dart:math' as math;
import 'dart:ui';

import '../../../../core/common/wire.dart';
import '../../../../domain/wiki/pinboard.dart';
import 'pinboard_element.dart';

/// How a connection is drawn: its line ([PinboardLines]) and its arrow heads
/// ([PinboardArrows]) — `null` each for the plain line.
typedef PinboardEdgeStyle = ({String? line, String? arrows});

/// The ways of drawing a connection offered to choose from.
const pinboardEdgeStyles = <PinboardEdgeStyle>[
  (line: null, arrows: null),
  (line: null, arrows: PinboardArrows.end),
  (line: null, arrows: PinboardArrows.both),
  (line: PinboardLines.dashed, arrows: null),
  (line: PinboardLines.dashed, arrows: PinboardArrows.end),
  (line: PinboardLines.dotted, arrows: null),
];

/// Draws a connection from [start] through the quadratic curve's [control] to
/// [end] with [paint]: dashed or dotted as [style] says, with arrow heads where it
/// says — each at least [minHead] long. Of a dashed or dotted line, only the dashes
/// within [cull] are drawn, where it is given.
void paintPinboardLine(
  Canvas canvas, {
  required Offset start,
  required Offset control,
  required Offset end,
  required Paint paint,
  required PinboardEdgeStyle style,
  required double minHead,
  Rect? cull,
}) {
  final width = paint.strokeWidth;
  final head = math.max(width * _headPerWidth, minHead);
  final arrows = style.arrows;
  final atEnd = arrows == PinboardArrows.end || arrows == PinboardArrows.both;
  final atStart =
      arrows == PinboardArrows.start || arrows == PinboardArrows.both;
  final endward = _unit(end - control, fallback: end - start);
  final startward = _unit(start - control, fallback: start - end);
  // Under a head the line stops short: its round end poked out of the tip.
  final from = atStart ? start - startward * head * _underHead : start;
  final to = atEnd ? end - endward * head * _underHead : end;
  final path = Path()
    ..moveTo(from.dx, from.dy)
    ..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy);
  switch (style.line) {
    case PinboardLines.dashed:
      _dashes(
        canvas,
        path,
        paint,
        dash: math.max(width * _dashPerWidth, minHead / 2),
        gap: math.max(width * _gapPerWidth, minHead / 2),
        cull: cull,
      );
    case PinboardLines.dotted:
      _dashes(
        canvas,
        path,
        paint..strokeCap = .round,
        dash: 0,
        gap: math.max(width * _dotGapPerWidth, minHead / 3),
        cull: cull,
      );
    default:
      canvas.drawPath(path, paint);
  }
  final fill = Paint()..color = paint.color;
  if (atEnd) _head(canvas, end, endward, head, fill);
  if (atStart) _head(canvas, start, startward, head, fill);
}

/// A kind of connection in a choice's circle: a line across it.
void paintEdgeGlyph(
  Canvas canvas,
  Size size,
  Color color,
  PinboardEdgeStyle style,
) {
  final y = size.height / 2;
  paintPinboardLine(
    canvas,
    start: Offset(_glyphInset, y),
    control: Offset(size.width / 2, y),
    end: Offset(size.width - _glyphInset, y),
    paint: Paint()
      ..color = color
      ..style = .stroke
      ..strokeCap = .round
      ..strokeWidth = _glyphLine,
    style: style,
    minHead: _glyphHead,
  );
}

/// A shape the pen draws, in a choice's circle.
void paintShapeGlyph(
  Canvas canvas,
  Size size,
  Color color,
  PinboardPenShape shape,
) {
  final diagonal = shape == .line || shape == .arrow;
  final from = diagonal
      ? Offset(_glyphInset, size.height - _glyphInset)
      : const Offset(_glyphInset, _glyphInset);
  final to = diagonal
      ? Offset(size.width - _glyphInset, _glyphInset)
      : Offset(size.width - _glyphInset, size.height - _glyphInset);
  paintStroke(
    canvas,
    penShapeOutline(shape, from, to, head: _glyphHead),
    color,
    _glyphLine,
  );
}

/// Where a note's text stands, in a choice's circle: three short lines at that place
/// of a square.
void paintTextAlignGlyph(Canvas canvas, Size size, Color color, String? align) {
  final box = (Offset.zero & size).deflate(_glyphInset);
  final paint = Paint()
    ..color = color
    ..strokeCap = .round
    ..strokeWidth = _glyphLine;
  final across = switch (align) {
    PinboardTextAligns.topCenter ||
    PinboardTextAligns.center ||
    PinboardTextAligns.bottomCenter => 0.5,
    PinboardTextAligns.topRight ||
    PinboardTextAligns.middleRight ||
    PinboardTextAligns.bottomRight => 1.0,
    _ => 0.0,
  };
  final upDown = switch (align) {
    PinboardTextAligns.middleLeft ||
    PinboardTextAligns.center ||
    PinboardTextAligns.middleRight => 0.5,
    PinboardTextAligns.bottomLeft ||
    PinboardTextAligns.bottomCenter ||
    PinboardTextAligns.bottomRight => 1.0,
    _ => 0.0,
  };
  final gap = box.height * _alignLineGap;
  final block = gap * (_alignLines.length - 1);
  final top = box.top + (box.height - block) * upDown;
  for (final (index, share) in _alignLines.indexed) {
    final length = box.width * share;
    final left = box.left + (box.width - length) * across;
    final y = top + index * gap;
    canvas.drawLine(Offset(left, y), Offset(left + length, y), paint);
  }
}

/// The three lines of [paintTextAlignGlyph], as shares of the square, and the room
/// between them.
const _alignLines = [0.7, 0.45, 0.6];
const _alignLineGap = 0.22;

Offset _unit(Offset vector, {required Offset fallback}) {
  final use = vector.distance == 0 ? fallback : vector;
  return use.distance == 0 ? Offset.zero : use / use.distance;
}

void _head(
  Canvas canvas,
  Offset tip,
  Offset direction,
  double length,
  Paint fill,
) {
  final back = tip - direction * length;
  final side = Offset(-direction.dy, direction.dx) * length * _headHalfWidth;
  canvas.drawPath(
    Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(back.dx + side.dx, back.dy + side.dy)
      ..lineTo(back.dx - side.dx, back.dy - side.dy)
      ..close(),
    fill,
  );
}

/// [path] dashed, drawn at once — a long line has hundreds of dashes, and each its
/// own drawing took twice as long. Only those near [cull] are worked out: a dash
/// starting farther out than its length and the line's thickness cannot reach it.
void _dashes(
  Canvas canvas,
  Path path,
  Paint paint, {
  required double dash,
  required double gap,
  Rect? cull,
}) {
  // A dot is a dash of no length: the round end makes it a dot.
  final piece = math.max(dash, _dot);
  final near = cull?.inflate(piece + paint.strokeWidth);
  final dashes = Path();
  for (final metric in path.computeMetrics()) {
    for (double at = 0; at < metric.length; at += dash + gap) {
      if (near != null &&
          !near.contains(metric.getTangentForOffset(at)?.position ?? .zero)) {
        continue;
      }
      dashes.addPath(
        metric.extractPath(at, math.min(at + piece, metric.length)),
        Offset.zero,
      );
    }
  }
  canvas.drawPath(dashes, paint);
}

/// An arrow head's length and half its width, by the line's thickness.
const _headPerWidth = 3.5;
const _headHalfWidth = 0.45;

/// How much of the head the line stops short by.
const _underHead = 0.8;
const _dashPerWidth = 3.0;
const _gapPerWidth = 2.5;
const _dotGapPerWidth = 2.5;
const _dot = 0.01;

/// A glyph's room to the circle's edge, its line, and its arrow heads.
const _glyphInset = 3.0;
const _glyphLine = 2.0;
const _glyphHead = 7.0;
