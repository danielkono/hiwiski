import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import '../../domain/wiki/pinboard.dart';
import '../ui/color_tokens.dart';
import 'hiwiski_tokens.dart';

/// How an element or a connection of a pinboard is coloured in the current theme.
///
/// A pinboard's colour is either an accent token or a colour of the family's own
/// (`#RRGGBB`). The tokens are the design's, one value each for light and dark. An own
/// colour is one value for both themes, so it is adapted here:
///
/// - **on a surface** — an element's fill — it stays exactly as chosen, and the text on
///   it is dark or light, whichever reads better: the element brings its background
///   along, whatever the theme;
/// - **on the canvas** — a line, a label, a snippet without a surface — it keeps its hue
///   and changes its tone until it stands out from the canvas, or a navy line would
///   vanish in the dark theme and a yellow one in the light.
@immutable
class PinboardPaint {
  const PinboardPaint({
    required this.fill,
    required this.onFill,
    required this.border,
    required this.line,
  });

  /// Resolves [color] (as stored) in [context]'s theme.
  factory PinboardPaint.of(BuildContext context, String? color) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final canvas = scheme.surface;
    return switch (PinboardColor.parse(color)) {
      null => .new(
        fill: scheme.surfaceContainerHigh,
        onFill: scheme.onSurface,
        border: scheme.outlineVariant,
        line: scheme.outline,
      ),
      TokenColor(:final token) => () {
        final accent = tokens.accent(accentOf(token));
        return PinboardPaint(
          fill: accent,
          onFill: tokens.onAccent,
          border: accent,
          line: readableOn(accent, canvas),
        );
      }(),
      OwnColor(:final rgb, :final alpha) => () {
        final own = Color(0xFF000000 | rgb);
        // See-through, the surface shows the canvas under it: its text is chosen
        // against what is seen, its outline keeps the colour whole.
        final fill = own.withAlpha(alpha);
        return PinboardPaint(
          fill: fill,
          onFill: inkOn(Color.alphaBlend(fill, canvas), scheme),
          border: own,
          line: readableOn(own, canvas).withAlpha(alpha),
        );
      }(),
    };
  }

  /// An element's surface.
  final Color fill;

  /// The text on [fill].
  final Color onFill;

  /// The outline around [fill].
  final Color border;

  /// A line, a label or a text standing on the canvas itself.
  final Color line;

  /// The colour a stored value shows as in a swatch — the chosen colour itself.
  static Color swatchOf(BuildContext context, PinboardColor color) =>
      switch (color) {
        TokenColor(:final token) => context.tokens.accent(accentOf(token)),
        OwnColor(:final rgb, :final alpha) => Color(
          0xFF000000 | rgb,
        ).withAlpha(alpha),
      };

  /// The colour a text of [color] (as stored) is drawn in on [background]: the
  /// chosen one, its tone moved only where it would not read there — `null` for none
  /// chosen.
  ///
  /// A see-through [background] is measured as it is seen, over the canvas: taken
  /// whole, a pale see-through fill counted as its strong colour, and a text that
  /// read on that was lost on what showed.
  static Color? textOf(BuildContext context, String? color, Color background) =>
      switch (PinboardColor.parse(color)) {
        final PinboardColor chosen => readableOn(
          swatchOf(context, chosen),
          Color.alphaBlend(background, Theme.of(context).colorScheme.surface),
          ratio: _textRatio,
        ),
        null => null,
      };

  /// What WCAG asks of text.
  static const _textRatio = 4.5;

  /// [color] as an own colour stores it — its red, green and blue, and its alpha.
  static OwnColor ownOf(Color color) {
    final argb = color.toARGB32();
    return OwnColor(argb & _rgbBits, alpha: argb >>> _alphaShift);
  }

  static const _rgbBits = 0xFFFFFF;
  static const _alphaShift = 24;

  /// The scheme's dark or light ink, whichever reads better on [background].
  static Color inkOn(Color background, ColorScheme scheme) {
    final dark = scheme.brightness == .light
        ? scheme.onSurface
        : scheme.surface;
    final light = scheme.brightness == .light
        ? scheme.surface
        : scheme.onSurface;
    return contrast(dark, background) >= contrast(light, background)
        ? dark
        : light;
  }

  /// [color] with its tone moved — away from [background] — until the two stand at
  /// least [ratio] apart; its hue stays. 3:1 is what WCAG asks of lines and large
  /// shapes.
  static Color readableOn(Color color, Color background, {double ratio = 3}) {
    if (contrast(color, background) >= ratio) return color;
    final hct = Hct.fromInt(color.toARGB32());
    final darker = background.computeLuminance() > _midLuminance;
    final step = darker ? -_toneStep : _toneStep;
    for (double tone = hct.tone; tone >= 0 && tone <= _maxTone; tone += step) {
      final candidate = Color(Hct.from(hct.hue, hct.chroma, tone).toInt());
      if (contrast(candidate, background) >= ratio) return candidate;
    }
    return darker ? Colors.black : Colors.white;
  }

  /// The WCAG contrast ratio of two colours.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + _flare) / (darker + _flare);
  }

  static const _midLuminance = 0.5;
  static const _toneStep = 2.0;
  static const _maxTone = 100.0;
  static const _flare = 0.05;

  @override
  bool operator ==(Object other) =>
      other is PinboardPaint &&
      other.fill == fill &&
      other.onFill == onFill &&
      other.border == border &&
      other.line == line;

  @override
  int get hashCode => Object.hash(fill, onFill, border, line);
}
