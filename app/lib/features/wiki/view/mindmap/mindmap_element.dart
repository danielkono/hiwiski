import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/common/wire.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/theme/mindmap_colors.dart';
import '../../../../components/member_avatar/view/member_avatar.dart';
import '../../../../components/rich_text/view/rich_image.dart';
import '../../../../domain/links/link_index.dart';
import '../../../../domain/wiki/mindmap.dart';
import 'mindmap_link.dart';
import 'mindmap_members.dart';
import 'mindmap_note.dart';

/// What a link element's address points to — `null` when that is not on this device
/// (deleted, or not shared).
typedef MindmapLinkTarget = LinkItem? Function(String target);

/// One element as it is drawn: its surface in its shape and colour, and what its kind
/// shows on it.
///
/// **The same at every zoom.** Drawn plainly from afar — a note's text without its
/// Markdown — the note was swapped for another while the map was zoomed through the
/// threshold, and its text and pictures flickered. Scaled, it stays what it is.
class MindmapElementView extends StatelessWidget {
  const MindmapElementView({
    super.key,
    required this.node,
    required this.linkTarget,
    this.interactive = false,
    this.zoom = 1,
    this.detail,
    this.selected = false,
    this.found = false,
    this.conflict = false,
    this.wrap,
    this.reach = .zero,
    this.editor,
  });

  final MindmapNode node;
  final MindmapLinkTarget linkTarget;

  /// Whether what is on the element takes taps and swipes — a note's pictures turned,
  /// a link chip followed, a target's content scrolled. Not while editing, where a
  /// drag moves the element, and not on the page's preview. A picture flies from here
  /// into its large view.
  final bool interactive;
  final double zoom;

  /// How large a unit of the map is on screen, where that is not [zoom]: a scene
  /// scaled from outside, as the page's preview is. A picture is loaded as sharp as
  /// it is seen.
  final double? detail;
  final bool selected;
  final bool found;
  final bool conflict;

  /// Wraps the element in the screen's gestures.
  final Widget Function(MindmapNode node, Widget child)? wrap;

  /// Room around the element in its box that takes a finger as the element does:
  /// a small one is taken as easily as a large one.
  final EdgeInsets reach;

  /// What stands in place of its text while it is written on the canvas — in the
  /// element's text style and colour.
  final Widget? editor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paint = MindmapPaint.of(context, node.color);
    final surface = node.hasSurface;
    final ink =
        MindmapPaint.textOf(
          context,
          node.textColor,
          surface ? paint.fill : scheme.surface,
        ) ??
        switch ((surface, node.color)) {
          (true, _) => paint.onFill,
          (false, null) => scheme.onSurface,
          // A snippet coloured before it had a text colour of its own.
          _ => paint.line,
        };
    final shape = shapeOf(
      node.effectiveShape,
      BorderSide(
        color: surface ? paint.border : Colors.transparent,
        width: HiwiskiMetrics.hairline,
      ),
    );
    final style = textStyleOf(context, node.textSize).copyWith(color: ink);
    final look = lookOf(node.kind);
    final shown = look.content((
      node: node,
      ink: ink,
      interactive: interactive,
      linkTarget: linkTarget,
      detail: detail ?? zoom,
      zoom: zoom,
    ));
    final content = DefaultTextStyle.merge(
      style: style,
      child: IconTheme.merge(
        data: IconThemeData(color: ink),
        child:
            editor ??
            (look.ownTouches
                ? shown
                : IgnorePointer(ignoring: !interactive, child: shown)),
      ),
    );
    Widget body = Padding(
      padding: insetOf(node),
      child: ClipRect(child: content),
    );
    if (surface) {
      body = DecoratedBox(
        decoration: ShapeDecoration(shape: shape, color: paint.fill),
        position: .background,
        child: body,
      );
    }
    final frame = selected || found;
    final drawn = Semantics(
      container: true,
      label: look.name(context, node),
      child: Stack(
        clipBehavior: .none,
        fit: .expand,
        children: [
          body,
          if (frame)
            Positioned.fill(
              // A little room between the element and its frame, the same on
              // screen at every zoom: tight around a snippet, the frame touched its
              // letters.
              left: -HiwiskiMetrics.mindmapFrameGap / zoom,
              top: -HiwiskiMetrics.mindmapFrameGap / zoom,
              right: -HiwiskiMetrics.mindmapFrameGap / zoom,
              bottom: -HiwiskiMetrics.mindmapFrameGap / zoom,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: shapeOf(
                      surface ? node.effectiveShape : look.frame,
                      BorderSide(
                        color: selected
                            ? scheme.primary
                            : context.tokens.highlight.foreground,
                        width: HiwiskiMetrics.strokeBold / zoom,
                        strokeAlign: BorderSide.strokeAlignOutside,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (conflict)
            Positioned(
              right: -HiwiskiMetrics.icon20 / 2 / zoom,
              top: -HiwiskiMetrics.icon20 / 2 / zoom,
              child: ExcludeSemantics(
                child: Container(
                  width: HiwiskiMetrics.icon20 / zoom,
                  height: HiwiskiMetrics.icon20 / zoom,
                  decoration: ShapeDecoration(
                    shape: const CircleBorder(),
                    color: scheme.tertiary,
                  ),
                  child: Icon(
                    HiwiskiSymbols.merge,
                    size: HiwiskiMetrics.icon16 / zoom,
                    color: scheme.onTertiary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    final reached = reach == .zero
        ? drawn
        : Stack(
            fit: .expand,
            children: [
              const _Reach(),
              Padding(padding: reach, child: drawn),
            ],
          );
    return wrap?.call(node, reached) ?? reached;
  }

  /// How an element of [kind] is drawn and named. A kind this app does not know is
  /// a placeholder that says so.
  static MindmapKindLook lookOf(String kind) => _looks[kind] ?? _unknownLook;

  /// One entry per kind — next to what the kind allows ([MindmapKind]) and how it
  /// is placed and edited on the map's screen (docs/development/mindmap.md).
  static final Map<String, MindmapKindLook> _looks = {
    MindmapKinds.plain: MindmapKindLook(
      icon: HiwiskiSymbols.title,
      name: (_, node) => node.text,
      content: _PlainContent.new,
    ),
    MindmapKinds.note: MindmapKindLook(
      icon: HiwiskiSymbols.stickyNote2,
      name: (_, node) => plainOfMarkdown(node.text),
      content: (content) => MindmapNote(node: content.node, ink: content.ink),
    ),
    MindmapKinds.image: MindmapKindLook(
      icon: HiwiskiSymbols.image,
      name: (context, _) => L.of(context).mindmapKindImage,
      content: (content) => _Picture(
        node: content.node,
        interactive: content.interactive,
        detail: content.detail,
      ),
    ),
    MindmapKinds.link: MindmapKindLook(
      icon: HiwiskiSymbols.link,
      name: (context, _) => L.of(context).mindmapKindLink,
      content: _LinkContent.new,
    ),
    MindmapKinds.member: MindmapKindLook(
      icon: HiwiskiSymbols.person,
      // Named as the family knows them, where they are known here.
      name: (context, node) =>
          MindmapMembers.of(context, memberIdOf(node.target))?.displayName ??
          L.of(context).mindmapKindMember,
      content: (content) => _Member(node: content.node),
      // Around a member's circle, a circle.
      frame: MindmapShapes.ellipse,
    ),
    MindmapKinds.drawing: MindmapKindLook(
      icon: HiwiskiSymbols.draw,
      name: (context, _) => L.of(context).mindmapKindDrawing,
      content: (content) => _Stroke(node: content.node, zoom: content.zoom),
      // Taken only near its line, at every zoom: the box around a stroke across
      // the map would cover what lies under it.
      ownTouches: true,
    ),
  };

  static final _unknownLook = MindmapKindLook(
    icon: HiwiskiSymbols.title,
    name: (_, node) => node.text,
    content: _UnknownContent.new,
  );

  /// What a picture element's picture flies from into its large view, and back.
  static Object pictureTagOf(String nodeId) => (_pictureTag, nodeId);

  static const _pictureTag = 'mindmap-picture';

  /// The symbol of an element's kind — on its tool and in lists.
  static IconData iconOfKind(String kind) => lookOf(kind).icon;

  /// The symbol of an item a link points to.
  static IconData iconOfItem(String itemType) => switch (itemType) {
    EntityTypes.todo => HiwiskiSymbols.taskAlt,
    EntityTypes.todoList => HiwiskiSymbols.checklist,
    EntityTypes.event => HiwiskiSymbols.event,
    EntityTypes.wikiPage => HiwiskiSymbols.description,
    _ => HiwiskiSymbols.link,
  };

  /// How much larger an element's text is at [size] than at the medium one — what a
  /// target's content shown in it is scaled by: it brings its own text styles.
  static double textScaleOf(BuildContext context, String? size) {
    final medium = textStyleOf(context, null).fontSize;
    final chosen = textStyleOf(context, size).fontSize;
    return medium == null || chosen == null ? 1 : chosen / medium;
  }

  /// The text style of an element's [size] — one of the names, or a size of its own
  /// in logical pixels ([mindmapTextPixels]).
  static TextStyle textStyleOf(BuildContext context, String? size) {
    final texts = context.texts;
    final pixels = mindmapTextPixels(size);
    if (pixels != null) {
      return (texts.bodyMedium ?? const TextStyle()).copyWith(
        fontSize: pixels.toDouble(),
      );
    }
    return switch (size) {
          MindmapTextSizes.small => texts.bodySmall,
          MindmapTextSizes.large => texts.titleMedium,
          MindmapTextSizes.xLarge => texts.headlineSmall,
          _ => texts.bodyMedium,
        } ??
        const TextStyle();
  }

  /// The room a plain snippet of [text] needs at [size], wrapped at [maxWidth] — what
  /// such an element is sized to, its longest line wide. Measured unscaled, as the map
  /// draws it ([MindmapScene]): the size is stored, and the same on every device.
  ///
  /// [writing]: as the field it is written in lays it out — with the leading of
  /// every line, and room for the cursor.
  static Size plainBoxOf(
    BuildContext context,
    String text,
    String? size, {
    required double maxWidth,
    bool writing = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyleOf(context, size)),
      textDirection: Directionality.of(context),
      textScaler: .noScaling,
      textWidthBasis: .longestLine,
      textHeightBehavior: writing ? null : plainHeight,
    )..layout(maxWidth: maxWidth - (writing ? _cursor : 0));
    final box = Size(
      painter.width.ceilToDouble() + _slack + (writing ? _cursor : 0),
      painter.height.ceilToDouble(),
    );
    painter.dispose();
    return box;
  }

  /// The cursor's room at the end of a line being written.
  static const _cursor = HiwiskiMetrics.space4;

  /// A snippet's lines without the leading above the first and below the last: the
  /// element ends where its text does, not a half line below it.
  static const plainHeight = TextHeightBehavior(
    applyHeightToFirstAscent: false,
    applyHeightToLastDescent: false,
  );

  /// A pixel or two to spare: another device's font may set the same words a hair
  /// wider, and they would wrap there.
  static const _slack = HiwiskiMetrics.hairline * 2;

  /// The room between an element's outline and its text: more where the outline
  /// curves in, so the text stays inside an ellipse or a diamond.
  static EdgeInsets insetOf(MindmapNode node) {
    if (!node.hasSurface) return .zero;
    // Its lines follow the shape itself: the outline keeps them [shapePad] inside.
    if (node.kind == MindmapKinds.note && MindmapNote.followsShape(node)) {
      return .zero;
    }
    final width = node.width.toDouble();
    final height = node.height.toDouble();
    return switch (node.effectiveShape) {
      // The largest rectangle inside an ellipse leaves (1 − 1/√2) / 2 of each side
      // free, about 0.15; a little more keeps the letters off the line.
      MindmapShapes.ellipse => .symmetric(
        horizontal: width * _curvedInset,
        vertical: height * _curvedInset,
      ),
      // Inside a diamond a quarter of each side — less, and the lines ran over its
      // slanted edges.
      MindmapShapes.diamond => .symmetric(
        horizontal: width * _diamondInset,
        vertical: height * _diamondInset,
      ),
      // The ends are half circles as wide as the shorter side: the text keeps off
      // them as it would inside such a circle. A pill as wide as it is high is one,
      // and its text ran out of it with the fixed room of a long pill.
      MindmapShapes.pill => .symmetric(
        horizontal: math.max(
          HiwiskiMetrics.space20,
          math.min(width, height) * _curvedInset,
        ),
        vertical: math.max(
          HiwiskiMetrics.space8,
          math.min(width, height) * _curvedInset,
        ),
      ),
      _ => const .all(HiwiskiMetrics.space12),
    };
  }

  /// The room between a shape and the lines that follow it.
  static const shapePad = HiwiskiMetrics.space12;

  static const _curvedInset = 0.18;
  static const _diamondInset = 0.27;

  /// The outline of [shape], drawn with [side].
  static ShapeBorder shapeOf(String shape, BorderSide side) => switch (shape) {
    MindmapShapes.rectangle => RoundedRectangleBorder(side: side),
    MindmapShapes.ellipse => OvalBorder(side: side),
    MindmapShapes.pill => StadiumBorder(side: side),
    MindmapShapes.diamond => StarBorder.polygon(
      side: side,
      sides: 4,
      squash: 1,
    ),
    _ => RoundedRectangleBorder(
      side: side,
      borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
    ),
  };
}

/// How an element of a kind is drawn and named — one entry per kind
/// ([MindmapElementView.lookOf]); what the kind allows is its [MindmapKind].
@immutable
class const MindmapKindLook({
  /// Its symbol: on its tool, in lists and in a search's results.
  required final IconData icon,

  /// What a screen reader says for an element of the kind.
  required final String Function(BuildContext context, MindmapNode node) name,

  /// What it shows, from what it is drawn with.
  required final Widget Function(MindmapContent content) content,

  /// Whether what it shows takes touches itself, while editing too — a stroke,
  /// taken only near its line. Anything else takes them only where the map is read.
  final bool ownTouches = false,

  /// The outline a selection follows around it where it has no surface of its own.
  final String frame = MindmapShapes.rounded,
});

/// What an element's content is drawn with: the element, the colour of its text,
/// whether it takes taps, how its targets read, and how large a unit of the map is
/// on screen ([MindmapElementView.detail], [MindmapElementView.zoom]).
typedef MindmapContent = ({
  MindmapNode node,
  Color ink,
  bool interactive,
  MindmapLinkTarget linkTarget,
  double detail,
  double zoom,
});

/// A snippet: as large as its text, the element measured to it ([plainBoxOf]).
class _PlainContent extends StatelessWidget {
  const _PlainContent(this.content);

  final MindmapContent content;

  @override
  Widget build(BuildContext context) => Text(
    content.node.text,
    overflow: .fade,
    softWrap: true,
    textHeightBehavior: MindmapElementView.plainHeight,
  );
}

/// A link: what it points to, as its preview shows it or by its title.
class _LinkContent extends StatelessWidget {
  const _LinkContent(this.content);

  final MindmapContent content;

  @override
  Widget build(BuildContext context) {
    final node = content.node;
    final address = node.target;
    final item = address == null ? null : content.linkTarget(address);
    // On the page's preview as on the canvas — but not within a target's content
    // shown already: a map linking its own page showed itself without end.
    if (item != null &&
        node.showsContent &&
        !MindmapLinkContent.within(context)) {
      return MindmapLinkContent(
        item: item,
        textScale: MindmapElementView.textScaleOf(context, node.textSize),
      );
    }
    return Row(
      children: [
        Icon(
          item == null
              ? HiwiskiSymbols.linkOff
              : MindmapElementView.iconOfItem(item.itemType),
          size: HiwiskiMetrics.icon20,
        ),
        const SizedBox(width: HiwiskiMetrics.space8),
        Expanded(
          child: Text(
            item?.title ?? L.of(context).mindmapLinkGone,
            maxLines: 2,
            overflow: .ellipsis,
          ),
        ),
      ],
    );
  }
}

/// A kind a newer app placed: kept as it is, shown as what it is not.
class _UnknownContent extends StatelessWidget {
  const _UnknownContent(this.content);

  final MindmapContent content;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      L.of(context).mindmapUnknownKind,
      textAlign: .center,
      overflow: .fade,
    ),
  );
}

/// A stroke drawn by hand, in the element's colour as chosen — see-through too, as a
/// marker — or the theme's ink.
class _Stroke extends StatelessWidget {
  const _Stroke({required this.node, required this.zoom});

  final MindmapNode node;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final color = switch (MindmapColor.parse(node.color)) {
      final MindmapColor chosen => MindmapPaint.swatchOf(context, chosen),
      null => Theme.of(context).colorScheme.onSurface,
    };
    return CustomPaint(
      painter: StrokePainter(
        fractions: strokeFractionsOf(node.points),
        box: Size(node.width.toDouble(), node.height.toDouble()),
        color: color,
        width: (node.strokeWidth ?? 1).toDouble(),
        reach: HiwiskiMetrics.minTapTarget / 4 / zoom,
      ),
    );
  }
}

/// A member element: their picture — or initial — in a circle as large as the
/// element, in a ring of the element's colour.
class _Member extends StatelessWidget {
  const _Member({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final member = MindmapMembers.of(context, memberIdOf(node.target));
    final side = math.min(node.width, node.height).toDouble();
    final ring = math.max(HiwiskiMetrics.strokeBold, side * _ringShare);
    return Center(
      child: Container(
        width: side,
        height: side,
        padding: .all(ring),
        decoration: ShapeDecoration(
          shape: const CircleBorder(),
          // The ring is the element's colour itself, see-through as chosen — not
          // the outline a surface keeps whole around a see-through fill.
          color: node.color == null
              ? scheme.primary
              : MindmapPaint.of(context, node.color).fill,
        ),
        child: member == null
            // No longer in the family, or not known here yet.
            ? CircleAvatar(
                backgroundColor: scheme.surfaceContainerHighest,
                child: Icon(
                  HiwiskiSymbols.person,
                  size: side / 2,
                  color: scheme.onSurfaceVariant,
                ),
              )
            : MemberAvatar.of(member, radius: side / 2 - ring),
      ),
    );
  }

  /// How thick the ring is, as a share of the circle.
  static const _ringShare = 0.05;
}

/// The room around a small element that takes a finger: nothing to see.
class _Reach extends StatelessWidget {
  const _Reach();

  @override
  Widget build(BuildContext context) =>
      const Listener(behavior: .opaque, child: SizedBox.expand());
}

/// A picture element: its picture, whole, filling the element — which has the
/// picture's shape.
///
/// As sharp as it is seen, and no sharper. The server's preview is shown first: tens
/// of kilobytes where a phone's photo is megabytes, and enough for a picture up to
/// the preview's size on screen. Only zoomed in past that, the original is loaded and
/// laid over the preview, which stays until it is there. A map of photos loaded
/// every original before — some megabytes each, kept in memory while shown, and
/// again on every visit in the browser, which keeps no images.
class _Picture extends StatefulWidget {
  const _Picture({
    required this.node,
    required this.interactive,
    required this.detail,
  });

  final MindmapNode node;
  final bool interactive;

  /// How large a unit of the map is on screen, zoom included.
  final double detail;

  @override
  State<_Picture> createState() => _PictureState();
}

class _PictureState extends State<_Picture> {
  /// Whether the original is wanted over the preview. Taken once the picture is shown
  /// past the preview's size, and let go only well below it again: right at the line,
  /// a zoom back and forth loaded and dropped it over and over.
  bool _original = false;

  /// Whether the original has arrived: then the preview under it goes — it is a
  /// JPEG, and where the picture is see-through it would show white.
  bool _originalShown = false;

  /// The pixels the picture takes across on screen.
  double _pixels = 0;

  /// The preview's width: its longest side is [_previewEdge], and the element has the
  /// picture's shape.
  double get _previewWidth =>
      _previewEdge *
      math.min(1, widget.node.width / math.max(1, widget.node.height));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _decide();
  }

  @override
  void didUpdateWidget(_Picture old) {
    super.didUpdateWidget(old);
    if (old.node.imageId != widget.node.imageId) {
      _original = false;
      _originalShown = false;
    }
    _decide();
  }

  void _decide() {
    _pixels =
        widget.node.width *
        widget.detail *
        MediaQuery.devicePixelRatioOf(context);
    if (_pixels > _previewWidth * _sharper) {
      _original = true;
    } else if (_pixels < _previewWidth * _softer) {
      _original = false;
      _originalShown = false;
    }
  }

  void _arrived(double _) {
    if (_originalShown || !mounted || !_original) return;
    setState(() => _originalShown = true);
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.node.imageId;
    if (id == null) {
      return const Center(
        child: Icon(HiwiskiSymbols.image, size: HiwiskiMetrics.icon48),
      );
    }
    const radius = Radius.circular(HiwiskiMetrics.radiusChip);
    // Decoded in steps of the size it is seen at: zooming through re-decodes now and
    // then, not in every frame, and the last one stays until the next is there.
    final picture = Stack(
      fit: .expand,
      children: [
        if (!_originalShown)
          RichImage(
            imageId: id,
            preview: true,
            decodeWidth: _decodeStep(math.min(_pixels, _previewWidth)),
            radius: radius,
          ),
        if (_original)
          RichImage(
            imageId: id,
            decodeWidth: _decodeStep(_pixels),
            radius: radius,
            // Over the preview: loading and failing show there, not twice.
            placeholder: false,
            onAspect: _arrived,
          ),
      ],
    );
    return widget.interactive
        ? Hero(
            tag: MindmapElementView.pictureTagOf(widget.node.id),
            child: picture,
          )
        : picture;
  }

  /// The longest side of the server's preview, in pixels.
  static const _previewEdge = 640.0;

  /// Past this share of the preview's width on screen the original is loaded; below
  /// this one it is let go again.
  static const _sharper = 1.25;
  static const _softer = 0.8;
}

/// [pixels] rounded up to the next width a picture is decoded at. The widths go up
/// by half an octave each — about 1.4 times the one before —, so a picture holds at
/// most twice the pixels it shows. Decoded at its exact width, a picture resized by
/// hand was decoded anew from the whole file in every frame of the drag.
int _decodeStep(double pixels) {
  if (pixels <= 1) return 1;
  // Half octaves; a width right on a step stays on it, whatever the rounding.
  final steps = (math.log(pixels) / math.ln2 * 2 - _onStep).ceil();
  return math.pow(2, steps / 2).ceil();
}

const _onStep = 1e-9;

/// A stroke through [fractions] of [box], [width] thick, smoothed through the middles
/// of its points; a single point is a dot. Hit within [reach] of the line only.
class StrokePainter extends CustomPainter {
  StrokePainter({
    required this.fractions,
    required this.box,
    required this.color,
    required this.width,
    required this.reach,
  });

  final List<Offset> fractions;

  /// The element's size, which the stroke spans — known before it is painted, for a
  /// hit on a painter that was not painted yet.
  final Size box;
  final Color color;
  final double width;
  final double reach;

  List<Offset> _points(Size size) => [
    for (final fraction in fractions)
      Offset(fraction.dx * size.width, fraction.dy * size.height),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    paintStroke(canvas, _points(size), color, width);
  }

  @override
  bool? hitTest(Offset position) =>
      distanceToStroke(position, _points(box)) <= width / 2 + reach;

  @override
  bool shouldRepaint(StrokePainter old) =>
      // The same stored stroke is the same list: read once ([strokeFractionsOf]).
      !identical(old.fractions, fractions) ||
      old.box != box ||
      old.color != color ||
      old.width != width ||
      old.reach != reach;
}

/// Paints [points] as a hand-drawn line [width] thick in [color].
void paintStroke(
  Canvas canvas,
  List<Offset> points,
  Color color,
  double width,
) {
  if (points.isEmpty) return;
  final paint = Paint()
    ..color = color
    ..strokeWidth = width
    ..strokeCap = .round
    ..strokeJoin = .round
    ..style = .stroke;
  if (points.length == 1) {
    canvas.drawCircle(points.single, width / 2, paint..style = .fill);
    return;
  }
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (int i = 1; i < points.length - 1; i++) {
    final middle = (points[i] + points[i + 1]) / 2;
    path.quadraticBezierTo(points[i].dx, points[i].dy, middle.dx, middle.dy);
  }
  path.lineTo(points.last.dx, points.last.dy);
  canvas.drawPath(path, paint);
}
