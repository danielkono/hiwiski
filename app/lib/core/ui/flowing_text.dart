import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../theme/hiwiski_metrics.dart';

/// The room across a line has, from [left] to [right], in the text's own
/// coordinates.
typedef FlowChord = ({double left, double right});

/// The outline a [FlowingText] fills.
@immutable
abstract class FlowOutline {
  const FlowOutline();

  /// The room across that lies inside the outline over the whole band from [top] to
  /// [bottom] of a box of [size] — `null` where there is none.
  FlowChord? chordOf(Size size, double top, double bottom);
}

/// The whole box: every line as wide as it.
class FlowBox extends FlowOutline {
  const FlowBox();

  @override
  FlowChord? chordOf(Size size, double top, double bottom) =>
      (left: 0, right: size.width);

  @override
  bool operator ==(Object other) => other is FlowBox;

  @override
  int get hashCode => (FlowBox).hashCode;
}

/// One paragraph of a [FlowingText]: it starts on a line of its own.
@immutable
class FlowParagraph {
  const FlowParagraph(
    InlineSpan this.span, {
    this.gap = 0,
    this.keepsSpaces = false,
  }) : rule = null;

  /// A line across the room, as a Markdown rule draws it.
  const FlowParagraph.rule(Color this.rule, {this.gap = 0})
    : span = null,
      keepsSpaces = false;

  final InlineSpan? span;
  final Color? rule;

  /// The room above it, below the paragraph before.
  final double gap;

  /// Whether spaces at the start of a line stay: in code they indent it.
  final bool keepsSpaces;

  @override
  bool operator ==(Object other) =>
      other is FlowParagraph &&
      other.span == span &&
      other.rule == rule &&
      other.gap == gap &&
      other.keepsSpaces == keepsSpaces;

  @override
  int get hashCode => Object.hash(span, rule, gap, keepsSpaces);
}

/// Text that fills an outline line by line: each line as wide as the outline is
/// over its height — a circle's lines short at its top and bottom and long in its
/// middle. A [Text] has one width for all its lines and cannot do this.
///
/// The lines stand at [place]: across, each within its own room; up and down, the
/// whole text within the room the outline leaves. A text taller than its box starts
/// at the top, and what does not fit is not shown. A word is broken only where even
/// the widest room is too narrow for it; elsewhere it moves down to where it fits.
///
/// The widgets of the [WidgetSpan]s — link chips, pictures — stand in the lines as
/// in a [Text.rich]. The box is as large as it is given: it fills a bounded box.
class FlowingText extends MultiChildRenderObjectWidget {
  FlowingText({
    super.key,
    required this.paragraphs,
    this.outline = const FlowBox(),
    this.place = AlignmentDirectional.topStart,
  }) : super(
         children: [for (final span in widgetSpansOf(paragraphs)) span.child],
       );

  final List<FlowParagraph> paragraphs;
  final FlowOutline outline;
  final AlignmentGeometry place;

  /// The widget spans of [paragraphs] in the order their widgets are children.
  static List<WidgetSpan> widgetSpansOf(List<FlowParagraph> paragraphs) {
    final spans = <WidgetSpan>[];
    for (final paragraph in paragraphs) {
      paragraph.span?.visitChildren((span) {
        if (span is WidgetSpan) spans.add(span);
        return true;
      });
    }
    return spans;
  }

  @override
  RenderFlowingText createRenderObject(BuildContext context) => .new(
    paragraphs: paragraphs,
    outline: outline,
    place: place,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
  );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderFlowingText renderObject,
  ) => renderObject
    ..paragraphs = paragraphs
    ..outline = outline
    ..place = place
    ..textDirection = Directionality.of(context)
    ..textScaler = MediaQuery.textScalerOf(context)
    ..locale = Localizations.maybeLocaleOf(context);
}

class _FlowParentData extends ContainerBoxParentData<RenderBox> {
  /// Whether it stands in a line: one past the end of a text cut short does not.
  bool shown = false;
}

/// One line as it is drawn: its text, or a rule.
class _Line {
  _Line.text(TextPainter this.painter, this.offset) : rule = null, width = 0;

  _Line.rule(Color this.rule, this.offset, this.width) : painter = null;

  final TextPainter? painter;
  final Color? rule;
  final Offset offset;
  final double width;
}

/// The lines of one try at placing the text, starting at a height.
class _Flow {
  final lines = <_Line>[];

  /// By child: where its widget stands and how wide the room it was laid out in.
  final placed = <int, (Offset, double)>{};

  /// The top of the first line and the bottom of the last.
  double? top;
  double bottom = 0;

  /// Whether some of the text found no room.
  bool overflow = false;

  void dispose() {
    for (final line in lines) {
      line.painter?.dispose();
    }
  }
}

/// The text of one paragraph as it is cut into lines.
class _Piece {
  _Piece(this.span) : text = span.toPlainText(includeSemanticsLabels: false) {
    int position = 0;
    span.visitChildren((child) {
      if (child is PlaceholderSpan) {
        holders.add(position++);
      } else if (child is TextSpan) {
        position += child.text?.length ?? 0;
      }
      return true;
    });
  }

  final InlineSpan span;

  /// The text as [TextPainter] counts it: a placeholder is one character.
  final String text;

  /// Where each placeholder stands in [text].
  final holders = <int>[];

  /// The part from [start] to [end].
  InlineSpan slice(int start, int end) {
    int position = 0;
    InlineSpan? cut(InlineSpan span) {
      if (span is PlaceholderSpan) {
        final at = position++;
        return at >= start && at < end ? span : null;
      }
      if (span is! TextSpan) return null;
      String? text;
      if (span.text case final own?) {
        final from = position;
        position += own.length;
        final first = math.max(start, from) - from;
        final last = math.min(end, position) - from;
        if (last > first) text = own.substring(first, last);
      }
      final children = <InlineSpan>[
        for (final child in span.children ?? const <InlineSpan>[]) ?cut(child),
      ];
      if (text == null && children.isEmpty) return null;
      return TextSpan(
        text: text,
        children: children.isEmpty ? null : children,
        style: span.style,
        recognizer: span.recognizer,
        mouseCursor: span.mouseCursor,
        onEnter: span.onEnter,
        onExit: span.onExit,
        locale: span.locale,
        spellOut: span.spellOut,
      );
    }

    return cut(span) ?? const TextSpan();
  }

  /// Whether a line ending at [at] would break a word — not at a space, a hyphen or
  /// a widget.
  bool breaksWordAt(int at) =>
      at > 0 &&
      at < text.length &&
      !_breakable(text.codeUnitAt(at - 1)) &&
      !_breakable(text.codeUnitAt(at));

  /// Where the word around [at] starts and ends.
  (int, int) wordAround(int at) {
    int start = at;
    while (start > 0 && !_breakable(text.codeUnitAt(start - 1))) {
      start--;
    }
    int end = at;
    while (end < text.length && !_breakable(text.codeUnitAt(end))) {
      end++;
    }
    return (start, end);
  }

  static bool _breakable(int unit) =>
      unit == _space ||
      unit == _newline ||
      unit == _hyphen ||
      unit == _placeholder ||
      unit == _tab;
}

const _space = 0x20;
const _newline = 0x0A;
const _hyphen = 0x2D;
const _tab = 0x09;
const _placeholder = 0xFFFC;

class RenderFlowingText extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FlowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FlowParentData> {
  RenderFlowingText({
    required List<FlowParagraph> paragraphs,
    required this._outline,
    required this._place,
    required this._textDirection,
    required this._textScaler,
    this._locale,
  }) : _paragraphs = paragraphs,
       _spans = FlowingText.widgetSpansOf(paragraphs);

  List<FlowParagraph> _paragraphs;
  List<WidgetSpan> _spans;
  set paragraphs(List<FlowParagraph> value) {
    if (identical(_paragraphs, value) || listEquals(value, _paragraphs)) {
      return;
    }
    _paragraphs = value;
    _spans = FlowingText.widgetSpansOf(value);
    markNeedsLayout();
  }

  FlowOutline _outline;
  set outline(FlowOutline value) {
    if (value == _outline) return;
    _outline = value;
    markNeedsLayout();
  }

  AlignmentGeometry _place;
  set place(AlignmentGeometry value) {
    if (value == _place) return;
    _place = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  TextScaler _textScaler;
  set textScaler(TextScaler value) {
    if (value == _textScaler) return;
    _textScaler = value;
    markNeedsLayout();
  }

  Locale? _locale;
  set locale(Locale? value) {
    if (value == _locale) return;
    _locale = value;
    markNeedsLayout();
  }

  List<_Line> _lines = const [];

  /// The lines of text as they stand — where each is drawn, in this box, and what
  /// it says. For tests: what is drawn by hand is no `Text` a finder finds.
  @visibleForTesting
  List<({Rect rect, String text})> get lines => [
    for (final line in _lines)
      if (line.painter case final painter?)
        (rect: line.offset & painter.size, text: painter.plainText),
  ];

  /// Tries at standing in the middle or at the bottom: each moves the text by
  /// what the last one missed, as a line moving down where the room is narrow
  /// changes how tall the text is.
  static const _settleTries = 6;

  /// Tries at a line's height: a line taller than guessed needs the room of its
  /// whole height.
  static const _heightTries = 3;

  /// Characters laid out at a time to find where a line ends — more when one line
  /// takes them all.
  static const _window = 160;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FlowParentData) {
      child.parentData = _FlowParentData();
    }
  }

  @override
  void dispose() {
    _disposeLines(_lines);
    super.dispose();
  }

  static void _disposeLines(List<_Line> lines) {
    for (final line in lines) {
      line.painter?.dispose();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  double computeMinIntrinsicHeight(double width) => 0;

  @override
  double computeMaxIntrinsicHeight(double width) => 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
    Size(
      constraints.maxWidth,
      constraints.hasBoundedHeight ? constraints.maxHeight : 0,
    ),
  );

  @override
  void performLayout() {
    assert(constraints.hasBoundedWidth, 'A FlowingText needs a width.');
    final children = getChildrenAsList();
    assert(children.length == _spans.length, 'One child per widget span.');
    final bounded = constraints.hasBoundedHeight;
    final room = Size(
      constraints.maxWidth,
      bounded ? constraints.maxHeight : double.infinity,
    );
    // Without a height there is no outline to fill but the width.
    final outline = bounded ? _outline : const FlowBox();
    final place = _place.resolve(_textDirection);
    final across = (place.x + 1) / 2;
    final upDown = (place.y + 1) / 2;

    _Flow flow = _flow(room, outline, 0, across, children);
    if (bounded && upDown > 0 && !flow.overflow && flow.top != null) {
      double start = 0;
      for (int tries = 0; tries < _settleTries; tries++) {
        final top = flow.top;
        if (top == null) break;
        final shift = upDown * (room.height - (flow.bottom - top)) - top;
        if (shift.abs() < HiwiskiMetrics.hairline / 2) break;
        final next = _flow(
          room,
          outline,
          math.max(0, start + shift),
          across,
          children,
        );
        if (next.overflow || next.top == null) {
          next.dispose();
          break;
        }
        flow.dispose();
        flow = next;
        start = math.max(0, start + shift);
      }
    }

    // A later try laid the widgets out in other rooms: back to the one kept.
    for (final (index, child) in children.indexed) {
      final data = child.parentData as _FlowParentData;
      final at = flow.placed[index];
      data.shown = at != null;
      child.layout(
        BoxConstraints(maxWidth: at?.$2 ?? room.width),
        parentUsesSize: true,
      );
      data.offset = at?.$1 ?? .zero;
    }
    _disposeLines(_lines);
    _lines = flow.lines;
    size = constraints.constrain(
      Size(room.width, bounded ? room.height : flow.bottom),
    );
  }

  _Flow _flow(
    Size room,
    FlowOutline outline,
    double start,
    double across,
    List<RenderBox> children,
  ) {
    final flow = _Flow();
    double y = start;
    int first = 0;
    for (final (index, paragraph) in _paragraphs.indexed) {
      if (index > 0) y += paragraph.gap;
      final piece = switch (paragraph.span) {
        final span? => _Piece(span),
        null => null,
      };
      y = switch ((piece, paragraph.rule)) {
        (null, final rule?) => _rule(flow, room, outline, y, rule),
        (null, null) => y,
        (final piece?, _) => _paragraph(
          flow,
          room,
          outline,
          y,
          piece,
          keepsSpaces: paragraph.keepsSpaces,
          first: first,
          across: across,
          children: children,
        ),
      };
      first += piece?.holders.length ?? 0;
      if (flow.overflow) break;
    }
    flow.bottom = y;
    return flow;
  }

  double _rule(
    _Flow flow,
    Size room,
    FlowOutline outline,
    double top,
    Color color,
  ) {
    const band = HiwiskiMetrics.space16;
    for (double y = top; y < room.height; y += band / 4) {
      final chord = outline.chordOf(room, y, y + band);
      if (chord != null &&
          (chord.right > chord.left || !room.height.isFinite)) {
        flow.lines.add(
          _Line.rule(
            color,
            Offset(chord.left, y + band / 2),
            chord.right - chord.left,
          ),
        );
        flow.top ??= y;
        return y + band;
      }
    }
    flow.overflow = true;
    return room.height;
  }

  /// Lays [piece] out in lines from [top] on; returns the bottom of its last.
  double _paragraph(
    _Flow flow,
    Size room,
    FlowOutline outline,
    double top,
    _Piece piece, {
    required bool keepsSpaces,
    required int first,
    required double across,
    required List<RenderBox> children,
  }) {
    final text = piece.text;
    int at = keepsSpaces ? 0 : _skipSpaces(text, 0);
    double y = top;
    double height = 0;
    double? widest;
    while (at < text.length) {
      // Where the line goes and where it ends: down where the room is too narrow.
      double guess = height;
      int window = _window;
      FlowChord lineRoom = (left: 0, right: 0);
      int cut = at;
      double lineHeight = 0;
      int heightTries = 0;
      while (true) {
        if (y >= room.height) {
          flow.overflow = true;
          return y;
        }
        final chord = outline.chordOf(room, y, y + guess);
        if (chord == null || chord.right <= chord.left) {
          // No room further down either without a bottom to stop at.
          if (!room.height.isFinite) {
            flow.overflow = true;
            return y;
          }
          y += math.max(guess / 4, HiwiskiMetrics.space2);
          continue;
        }
        final width = chord.right - chord.left;
        final end = math.min(text.length, at + window);
        final painter = _painter(
          piece.slice(at, end),
          _dimensionsOf(piece, at, end, first, width, children),
          oneLine: true,
        )..layout(maxWidth: width);
        final metrics = painter.computeLineMetrics();
        final fitsWindow = !painter.didExceedMaxLines;
        final measured = metrics.isEmpty
            ? painter.height
            : metrics.first.height;
        final lineEnd =
            at + painter.getLineBoundary(const TextPosition(offset: 0)).end;
        painter.dispose();
        if (fitsWindow && end < text.length) {
          // The whole window fits on the line: the line may go on.
          window *= 2;
          continue;
        }
        if (measured > guess + HiwiskiMetrics.hairline / 2 &&
            heightTries++ < _heightTries) {
          guess = measured;
          continue;
        }
        widest ??= _widest(outline, room, measured);
        // A word wider than the line: broken only when no line is wide enough
        // for it. Otherwise it moves down — above the middle a round or pointed
        // outline widens; past it, it only narrows, and the text ends here.
        if (piece.breaksWordAt(lineEnd) &&
            width < widest - HiwiskiMetrics.hairline &&
            _widthOf(piece, lineEnd) <= widest) {
          if (y + measured / 2 >= room.height / 2) {
            flow.overflow = true;
            return y;
          }
          y += math.max(measured / 4, HiwiskiMetrics.space2);
          continue;
        }
        lineRoom = chord;
        cut = lineEnd;
        lineHeight = measured;
        break;
      }

      // What ends the line is not drawn: the break, and spaces before it.
      int end = cut;
      while (end > at &&
          (text.codeUnitAt(end - 1) == _newline ||
              text.codeUnitAt(end - 1) == _space)) {
        end--;
      }
      int next = cut;
      if (next < text.length &&
          text.codeUnitAt(next) == _newline &&
          (cut == at || text.codeUnitAt(cut - 1) != _newline)) {
        next++;
      }
      if (!keepsSpaces) next = _skipSpaces(text, next);
      if (next <= at) next = at + 1;

      flow.top ??= y;
      if (end > at) {
        final width = lineRoom.right - lineRoom.left;
        final line = _painter(
          piece.slice(at, end),
          _dimensionsOf(piece, at, end, first, width, children),
        )..layout();
        final x = lineRoom.left + (width - line.width) * across;
        flow.lines.add(_Line.text(line, Offset(x, y)));
        final boxes = line.inlinePlaceholderBoxes ?? const <TextBox>[];
        int box = 0;
        for (final (index, holder) in piece.holders.indexed) {
          if (holder < at || holder >= end || box >= boxes.length) continue;
          final place = boxes[box++];
          flow.placed[first + index] = (
            Offset(x + place.left, y + place.top),
            width,
          );
        }
      }
      y += lineHeight;
      height = lineHeight;
      at = next;
    }
    return y;
  }

  /// How wide the word of [piece] around [at] is.
  double _widthOf(_Piece piece, int at) {
    final (start, end) = piece.wordAround(at);
    final painter = _painter(piece.slice(start, end), const [])..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  static int _skipSpaces(String text, int from) {
    int at = from;
    while (at < text.length && text.codeUnitAt(at) == _space) {
      at++;
    }
    return at;
  }

  /// The room across a line of [height] has in the outline's middle — where a
  /// round or pointed outline is widest.
  static double _widest(FlowOutline outline, Size room, double height) {
    final chord = outline.chordOf(
      room,
      (room.height - height) / 2,
      (room.height + height) / 2,
    );
    return chord == null ? 0 : chord.right - chord.left;
  }

  /// The sizes of the widgets of [piece] from [start] to [end], each laid out in a
  /// room [width] wide.
  List<PlaceholderDimensions> _dimensionsOf(
    _Piece piece,
    int start,
    int end,
    int first,
    double width,
    List<RenderBox> children,
  ) => [
    for (final (index, holder) in piece.holders.indexed)
      if (holder >= start && holder < end)
        _dimensionOf(children[first + index], _spans[first + index], width),
  ];

  static PlaceholderDimensions _dimensionOf(
    RenderBox child,
    WidgetSpan span,
    double width,
  ) {
    child.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    final TextBaseline baseline = span.baseline ?? .alphabetic;
    return PlaceholderDimensions(
      size: child.size,
      alignment: span.alignment,
      baseline: span.baseline,
      baselineOffset: span.alignment == .baseline
          ? child.getDistanceToBaseline(baseline)
          : null,
    );
  }

  TextPainter _painter(
    InlineSpan text,
    List<PlaceholderDimensions> dimensions, {
    bool oneLine = false,
  }) => TextPainter(
    text: text,
    textDirection: _textDirection,
    textScaler: _textScaler,
    locale: _locale,
    maxLines: oneLine ? 1 : null,
  )..setPlaceholderDimensions(dimensions);

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    for (final line in _lines) {
      if (line.painter case final painter?) {
        painter.paint(canvas, offset + line.offset);
      } else if (line.rule case final color?) {
        final from = offset + line.offset;
        canvas.drawLine(
          from,
          from + Offset(line.width, 0),
          Paint()
            ..color = color
            ..strokeWidth = HiwiskiMetrics.hairline,
        );
      }
    }
    // After the text: a widget drawn on a layer of its own starts a new canvas.
    RenderBox? child = firstChild;
    while (child != null) {
      final data = child.parentData as _FlowParentData;
      if (data.shown) context.paintChild(child, offset + data.offset);
      child = data.nextSibling;
    }
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    RenderBox? child = lastChild;
    while (child != null) {
      final data = child.parentData as _FlowParentData;
      final current = child;
      if (data.shown &&
          result.addWithPaintOffset(
            offset: data.offset,
            position: position,
            hitTest: (result, transformed) =>
                current.hitTest(result, position: transformed),
          )) {
        return true;
      }
      child = data.previousSibling;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    visitChildren((child) {
      if ((child.parentData as _FlowParentData).shown) visitor(child);
    });
  }
}
