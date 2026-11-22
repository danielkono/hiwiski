import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';

/// How much of the surface under the screen's controls over the map covers it — the
/// title's, the corner's: nearly all, the map shows through only faintly.
const mindmapOverlayOpacity = 0.92;

/// One choice in the corner.
@immutable
class const MindmapCornerOption({
  required final Key key,
  required final IconData icon,
  required final String label,

  /// `null`: offered, but not possible now.
  required final VoidCallback? onTap,

  /// Switched on — the tool in hand.
  final bool on = false,

  /// What it is when held and dragged out onto the canvas — an element's kind;
  /// `null`: it is only tapped.
  final String? dragged,

  /// A colour shown instead of the symbol — the pen's.
  final Color? swatch,

  /// A drawing shown instead of the symbol — a kind of line, a shape — in the
  /// colour it is given.
  final MindmapGlyph? glyph,
});

/// Draws what a choice stands for into its circle, in [color].
typedef MindmapGlyph = void Function(Canvas canvas, Size size, Color color);

/// A button in the corner, and the choices it brings out.
@immutable
class const MindmapCornerMenu({
  required final Key key,
  required final IconData icon,
  required final String label,
  required final List<MindmapCornerOption> options,

  /// Whether one of its tools is in hand: its button stands out.
  final bool on = false,
});

/// A level below a choice: its own choices in the place of the menu's. [id] tells
/// one from another.
typedef MindmapCornerSubmenu = ({Object id, List<MindmapCornerOption> options});

/// Where everything in the corner stands, around the screen's corner: the button in
/// the middle ([back], from the corner), the ring of the buttons and the ring of the
/// choices, and the radius of the quarter circle behind them.
typedef MindmapCornerLayout = ({
  Offset back,
  double buttons,
  double options,
  double radius,
  EdgeInsets safe,
});

/// The corner's layout for a screen with [safe] insets: on a phone the choices on
/// the buttons' own ring, on a larger screen on the next one out.
MindmapCornerLayout mindmapCornerLayout({
  required bool compact,
  required EdgeInsets safe,
}) {
  const margin = HiwiskiMetrics.mindmapCornerMargin;
  const half = HiwiskiMetrics.minTapTarget / 2;
  final back = Offset(
    -(safe.right + margin + half),
    -(safe.bottom + margin + half),
  );
  final buttons = back.distance + HiwiskiMetrics.mindmapCornerRingGap;
  final options = compact
      ? buttons
      : buttons + HiwiskiMetrics.mindmapCornerRingStep;
  return (
    back: back,
    buttons: buttons,
    options: options,
    radius: options + half + HiwiskiMetrics.mindmapCornerPadding,
    safe: safe,
  );
}

/// The angles on [ring] between which something reaching [half] from its centre
/// stands clear of the screen's edges and its safe area — 0 points right, the angle
/// grows clockwise, the quarter runs from π (left of the corner) to 3π/2 (above it).
({double from, double to}) mindmapCornerArc(
  MindmapCornerLayout layout,
  double ring,
  double half,
) {
  const margin = HiwiskiMetrics.mindmapCornerMargin;
  double clear(double inset) =>
      math.asin(((inset + margin + half) / ring).clamp(0, 1));
  return (
    from: math.pi + clear(layout.safe.bottom),
    to: math.pi * 3 / 2 - clear(layout.safe.right),
  );
}

/// The editing controls in the screen's bottom right corner: a few round buttons on
/// a ring around the corner, each bringing its choices out of itself onto a ring —
/// on a phone the buttons' own, in their place; on a larger screen the next one out.
/// A choice may lead a level further: its choices come out of it in turn. However
/// many there are, they take the same room: those that do not fit are turned into
/// view along the ring — by a finger anywhere on it, on a choice too, by the mouse
/// or the wheel.
///
/// The button in the middle goes back a level, or — with something selected, whose
/// choices then stand there — lets go of it.
///
/// It lies in the very corner of the screen: its quarter circle reaches into the safe
/// area, its buttons stay out of it.
class MindmapCorner extends StatefulWidget {
  const MindmapCorner({
    super.key,
    required this.menus,
    required this.open,
    required this.onOpen,
    required this.compact,
    required this.backKey,
    required this.backLabel,
    required this.onBack,
    this.submenu,
    this.selection,
    this.onRelease,
    this.releaseKey,
    this.releaseLabel,
  });

  final List<MindmapCornerMenu> menus;

  /// Which of [menus] is open — `null`: none.
  final int? open;
  final ValueChanged<int?> onOpen;

  /// A level below a choice of the open menu, open in its place.
  final MindmapCornerSubmenu? submenu;

  /// A phone's layout: the choices on the buttons' own ring.
  final bool compact;

  /// The button in the middle, going back a level.
  final Key backKey;
  final String backLabel;
  final VoidCallback onBack;

  /// The choices of what is selected — shown instead of the menus while there are
  /// any.
  final List<MindmapCornerOption>? selection;
  final VoidCallback? onRelease;
  final Key? releaseKey;
  final String? releaseLabel;

  @override
  State<MindmapCorner> createState() => _MindmapCornerState();
}

class _MindmapCornerState extends State<MindmapCorner>
    with TickerProviderStateMixin {
  /// How far the choices are out of where they come from: 0 inside it, 1 on the
  /// ring.
  late final _out = AnimationController(vsync: this, duration: _coming);

  /// Settles the ring on a choice once the finger lets go.
  late final _settle = AnimationController(vsync: this, duration: _settleTime);

  /// The choices on the ring — kept while they go back.
  List<MindmapCornerOption>? _options;

  /// Whose choices they are: a menu's index, a submenu's id, [_selected] for the
  /// selection's; `null` for none.
  Object? _source;

  /// Where they came out of, from the corner.
  Offset? _origin;

  /// Whether they are going back, to be gone.
  bool _closing = false;

  /// Where the choice tapped last stood, from the corner: a submenu comes out of it.
  Offset? _tappedAt;

  /// How far the choices are turned along the ring, in radians.
  double _turned = 0;
  double _settleFrom = 0;
  double _settleTo = 0;

  /// The angle of the pointer turning them, last seen.
  double? _grabbed;

  late MindmapCornerLayout _layout;

  static const _selected = #selected;

  @override
  void initState() {
    super.initState();
    _out.addStatusListener(_gone);
    _settle.addListener(_settling);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _layout = mindmapCornerLayout(
      compact: widget.compact,
      safe: MediaQuery.paddingOf(context),
    );
    _follow();
  }

  @override
  void didUpdateWidget(MindmapCorner old) {
    super.didUpdateWidget(old);
    _layout = mindmapCornerLayout(
      compact: widget.compact,
      safe: MediaQuery.paddingOf(context),
    );
    _follow();
  }

  @override
  void dispose() {
    _out
      ..removeStatusListener(_gone)
      ..dispose();
    _settle
      ..removeListener(_settling)
      ..dispose();
    super.dispose();
  }

  /// Back where they came from: no choices any more. Only after going back —
  /// coming out again starts from 0 too, which reports the same.
  void _gone(AnimationStatus status) {
    if (status != .dismissed || !_closing) return;
    _closing = false;
    setState(() {
      _options = null;
      _source = null;
    });
  }

  void _settling() => setState(
    () => _turned =
        lerpDouble(
          _settleFrom,
          _settleTo,
          Curves.easeOut.transform(_settle.value),
        ) ??
        _settleTo,
  );

  /// Follows what the screen shows: other choices come out of where they belong,
  /// none go back into it.
  void _follow() {
    final open = widget.open;
    final menu = open != null && open < widget.menus.length ? open : null;
    // A level below belongs to the open menu — or to what is selected, whose
    // choices it then stands in place of.
    final submenu = menu == null && widget.selection == null
        ? null
        : widget.submenu;
    final (Object? source, List<MindmapCornerOption>? wanted) = switch ((
      widget.selection,
      submenu,
      menu,
    )) {
      (_, final sub?, _) => (sub.id, sub.options),
      (final selection?, null, _) => (_selected, selection),
      (null, null, final menu?) => (menu, widget.menus[menu].options),
      _ => (null, null),
    };
    if (wanted == null) {
      if (_options != null && !_closing) {
        _closing = true;
        unawaited(_out.reverse());
      }
      return;
    }
    final same = source == _source && _options != null;
    _options = wanted;
    final closing = _closing;
    _closing = false;
    if (same) {
      // Taken back while going: out again from where they are.
      if (closing) unawaited(_out.forward());
      return;
    }
    _origin = switch (source) {
      final int menu => _buttonAt(menu),
      _selected => _layout.back,
      _ => _tappedAt ?? _layout.back,
    };
    _source = source;
    _turned = 0;
    _settle.stop();
    unawaited(_out.forward(from: 0));
  }

  // --- Where everything stands, from the corner ----------------------------------

  static Offset _polar(double ring, double angle) =>
      Offset(math.cos(angle), math.sin(angle)) * ring;

  /// Where menu [index] has its button.
  Offset _buttonAt(int index) {
    const half = HiwiskiMetrics.minTapTarget / 2;
    final arc = mindmapCornerArc(_layout, _layout.buttons, half);
    final count = widget.menus.length;
    final angle = count < 2
        ? (arc.from + arc.to) / 2
        : arc.from + index * (arc.to - arc.from) / (count - 1);
    return _polar(_layout.buttons, angle);
  }

  /// The arc the choices stand on, and the angle between two.
  ({double from, double to}) get _arc => mindmapCornerArc(
    _layout,
    _layout.options,
    HiwiskiMetrics.mindmapCornerOption / 2,
  );
  double get _step =>
      2 *
      math.asin(
        ((HiwiskiMetrics.mindmapCornerOption +
                    HiwiskiMetrics.mindmapCornerSpacing) /
                2 /
                _layout.options)
            .clamp(0, 1),
      );

  double _angleOf(int index) => _arc.from + index * _step - _turned;

  // --- Turning ---------------------------------------------------------------------

  /// How far the choices can be turned: until the last one is in view.
  double _limit(int count) {
    final arc = _arc;
    return math.max(0, (count - 1) * _step - (arc.to - arc.from));
  }

  /// The angle of [local], a point of the corner's box, around the screen's corner.
  double _angleAt(Offset local) =>
      math.atan2(local.dy - _layout.radius, local.dx - _layout.radius);

  /// [by] as the short way round: level with the corner the angle jumps from -π to
  /// π, and a finger crossing there turned the choices all the way at once.
  static double _shortest(double by) => switch (by) {
    > math.pi => by - 2 * math.pi,
    < -math.pi => by + 2 * math.pi,
    _ => by,
  };

  void _turn(double by) {
    final options = _options;
    if (options == null) return;
    _settle.stop();
    setState(() => _turned = (_turned + by).clamp(0, _limit(options.length)));
  }

  /// Lets go of the ring with a choice where the first one stood.
  void _rest() {
    _grabbed = null;
    final options = _options;
    if (options == null) return;
    _settleFrom = _turned;
    _settleTo = ((_turned / _step).round() * _step).clamp(
      0,
      _limit(options.length),
    );
    unawaited(_settle.forward(from: 0));
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: _layout.radius,
    child: Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _turn(event.scrollDelta.dy / _layout.options);
        }
      },
      // Over the choices too: a finger on one turns the ring once it moves, and
      // taps it if it does not.
      child: GestureDetector(
        onPanStart: (details) => _grabbed = _angleAt(details.localPosition),
        onPanUpdate: (details) {
          final at = _angleAt(details.localPosition);
          final from = _grabbed ?? at;
          _grabbed = at;
          // The choices follow the finger along the ring: towards the left edge,
          // the later ones come into view from the top.
          _turn(_shortest(from - at));
        },
        onPanEnd: (_) => _rest(),
        onPanCancel: _rest,
        child: AnimatedBuilder(
          animation: _out,
          builder: (context, _) => _Layout(state: this),
        ),
      ),
    ),
  );

  static const _coming = Duration(milliseconds: 220);
  static const _settleTime = Duration(milliseconds: 160);
}

/// The corner as it stands at this moment of coming out or going back.
class _Layout extends StatelessWidget {
  const _Layout({required this.state});

  final _MindmapCornerState state;

  @override
  Widget build(BuildContext context) {
    final widget = state.widget;
    final layout = state._layout;
    final options = state._options;
    final out = Curves.easeOutCubic.transform(state._out.value);
    final settled = state._out.status == .completed;
    final source = state._source;
    // The selection's own choices, with the way to let go of it in the middle; a
    // level below them has the way back there instead.
    final selecting = source == _MindmapCornerState._selected;
    final aboutSelection = widget.selection != null;
    // The screen's corner, in the box.
    final corner = Offset(layout.radius, layout.radius);
    final origin = state._origin ?? layout.back;
    const option = HiwiskiMetrics.mindmapCornerOption;
    const button = HiwiskiMetrics.minTapTarget;
    final shown = options != null && out > 0;
    // On a phone the buttons make room for the choices; on a larger screen only a
    // selection's choices take their place.
    final buttonsGo = shown && (widget.compact || aboutSelection);
    return Stack(
      children: [
        if (shown)
          Positioned.fill(
            child: _Quarter(
              radius: layout.radius * (lerpDouble(_grownFrom, 1, out) ?? 1),
              opacity: out,
            ),
          ),
        for (final (index, menu) in widget.menus.indexed)
          if (!buttonsGo || out < 1)
            _Placed(
              // On a phone the button tapped goes into the middle, where the way
              // back then is.
              at:
                  corner +
                  (widget.compact && index == source
                      ? Offset.lerp(state._buttonAt(index), layout.back, out) ??
                            layout.back
                      : state._buttonAt(index)),
              size: button,
              opacity: buttonsGo ? 1 - out : 1,
              scale: buttonsGo ? 1 - out * _shrink : 1,
              touchable: !buttonsGo,
              child: _Round(
                key: menu.key,
                icon: menu.icon,
                label: menu.label,
                on: widget.open == index || menu.on,
                onTap: () => widget.onOpen(widget.open == index ? null : index),
              ),
            ),
        if (shown)
          _Placed(
            at: corner + layout.back,
            size: button,
            opacity: out,
            scale: lerpDouble(_grownFrom, 1, out) ?? 1,
            touchable: settled,
            child: selecting
                ? _Round(
                    key: widget.releaseKey,
                    icon: HiwiskiSymbols.close,
                    label: widget.releaseLabel ?? '',
                    on: false,
                    onTap: widget.onRelease,
                  )
                : _Round(
                    key: widget.backKey,
                    icon: HiwiskiSymbols.arrowBack,
                    label: widget.backLabel,
                    on: false,
                    onTap: widget.onBack,
                  ),
          ),
        if (shown)
          for (final (index, choice) in options.indexed)
            if (_fade(index) case final fade when fade > 0)
              _Placed(
                at:
                    corner +
                    (Offset.lerp(
                          origin,
                          _MindmapCornerState._polar(
                            layout.options,
                            state._angleOf(index),
                          ),
                          out,
                        ) ??
                        origin),
                size: option,
                opacity: out * fade,
                scale: lerpDouble(_grownFrom, 1, out) ?? 1,
                touchable: settled && fade > _halfway,
                child: _Option(
                  option: choice,
                  // A level below comes out of the choice that leads to it.
                  onTapped: () => state._tappedAt = _MindmapCornerState._polar(
                    layout.options,
                    state._angleOf(index),
                  ),
                ),
              ),
      ],
    );
  }

  /// How much of choice [index] shows: fading as it is turned past either end.
  double _fade(int index) {
    final arc = state._arc;
    final angle = state._angleOf(index);
    final past = math.max(arc.from - angle, angle - arc.to);
    return (1 - past / (state._step * _fadeWithin)).clamp(0, 1);
  }

  /// The share of their size the quarter and the choices grow from, and of the
  /// buttons' they shrink by as they make room.
  static const _grownFrom = 0.4;
  static const _shrink = 0.4;

  /// Past an end, a choice is gone within this share of the step between two.
  static const _fadeWithin = 0.6;
  static const _halfway = 0.5;
}

/// The quarter circle behind the choices, on the surface the title stands on. It
/// takes every pointer inside the curve — to turn the ring, and not to move the map
/// under it — and none outside.
class _Quarter extends StatelessWidget {
  const _Quarter({required this.radius, required this.opacity});

  final double radius;
  final double opacity;

  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: _QuarterClip(radius),
    child: Listener(
      behavior: .opaque,
      child: RepaintBoundary(
        child: ColoredBox(
          color: context.scheme.surfaceContainerHigh.withValues(
            alpha: mindmapOverlayOpacity * opacity,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

/// A quarter of a circle of [radius] around the bottom right corner of the box.
class _QuarterClip extends CustomClipper<Path> {
  const _QuarterClip(this.radius);

  final double radius;

  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width, size.height)
    ..lineTo(size.width - radius, size.height)
    ..arcToPoint(
      Offset(size.width, size.height - radius),
      radius: .circular(radius),
    )
    ..close();

  @override
  bool shouldReclip(_QuarterClip oldClipper) => oldClipper.radius != radius;
}

/// Something in the corner, centred on [at].
class _Placed extends StatelessWidget {
  const _Placed({
    required this.at,
    required this.size,
    required this.opacity,
    required this.scale,
    required this.touchable,
    required this.child,
  });

  final Offset at;
  final double size;
  final double opacity;
  final double scale;
  final bool touchable;
  final Widget child;

  @override
  Widget build(BuildContext context) => Positioned(
    left: at.dx - size / 2,
    top: at.dy - size / 2,
    width: size,
    height: size,
    child: IgnorePointer(
      ignoring: !touchable || opacity <= 0,
      child: Opacity(
        opacity: opacity.clamp(0, 1),
        child: Transform.scale(scale: scale, child: child),
      ),
    ),
  );
}

/// A round button in the corner: a menu, back, or letting go of what is selected.
class _Round extends StatelessWidget {
  const _Round({
    super.key,
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Semantics(
      button: true,
      toggled: on,
      label: label,
      excludeSemantics: true,
      child: Material(
        shape: const CircleBorder(),
        color: on ? context.scheme.primary : context.scheme.primaryContainer,
        elevation: HiwiskiMetrics.elevationMenu,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(
            icon,
            color: on
                ? context.scheme.onPrimary
                : context.scheme.onPrimaryContainer,
          ),
        ),
      ),
    ),
  );
}

/// A choice on the ring: its symbol in a circle, its name on hover and to a screen
/// reader.
class _Option extends StatelessWidget {
  const _Option({required this.option, required this.onTapped});

  final MindmapCornerOption option;

  /// Told before the choice acts, so that what it opens knows where it was.
  final VoidCallback onTapped;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final ink = option.on ? scheme.onSecondaryContainer : scheme.onSurface;
    final face = Opacity(
      opacity: option.onTap == null ? _unavailable : 1,
      child: Material(
        shape: CircleBorder(side: BorderSide(color: scheme.outlineVariant)),
        color: option.on ? scheme.secondaryContainer : scheme.surface,
        elevation: HiwiskiMetrics.elevationMenu,
        child: Center(
          child: switch ((option.swatch, option.glyph)) {
            (final swatch?, _) => Container(
              width: HiwiskiMetrics.swatchSize,
              height: HiwiskiMetrics.swatchSize,
              decoration: ShapeDecoration(
                shape: CircleBorder(
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                color: swatch,
              ),
            ),
            (null, final glyph?) => SizedBox.square(
              dimension: HiwiskiMetrics.icon24,
              child: CustomPaint(painter: _GlyphPainter(glyph, ink)),
            ),
            (null, null) => Icon(
              option.icon,
              size: HiwiskiMetrics.icon20,
              color: ink,
            ),
          },
        ),
      ),
    );
    final onTap = option.onTap;
    final tappable = Semantics(
      button: true,
      toggled: option.on,
      enabled: onTap != null,
      label: option.label,
      excludeSemantics: true,
      child: InkResponse(
        key: option.key,
        onTap: onTap == null
            ? null
            : () {
                onTapped();
                onTap();
              },
        radius: HiwiskiMetrics.mindmapCornerOption / 2,
        child: face,
      ),
    );
    final kind = option.dragged;
    if (kind == null) return Tooltip(message: option.label, child: tappable);
    // Held, then dragged out onto the canvas, it lands where the pointer lets go —
    // held, so that a finger moving at once turns the ring instead.
    return LongPressDraggable<String>(
      data: kind,
      delay: _hold,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        elevation: HiwiskiMetrics.elevationDrag,
        shape: const CircleBorder(),
        color: scheme.secondaryContainer,
        child: Padding(
          padding: const .all(HiwiskiMetrics.space8),
          child: Icon(option.icon, color: scheme.onSecondaryContainer),
        ),
      ),
      child: Tooltip(
        message: option.label,
        // Held, it is dragged: the name shows to the mouse only.
        triggerMode: .manual,
        child: tappable,
      ),
    );
  }

  static const _unavailable = 0.38;
  static const _hold = Duration(milliseconds: 250);
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.color);

  final MindmapGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => glyph(canvas, size, color);

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}
