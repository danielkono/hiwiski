import 'package:flutter/painting.dart';

/// The accent colors for calendars, lists, groups and members.
///
/// What gets stored is **a token, not a hex value**: a stored hex
/// value would be unreadable in one of the two themes, and a stored hue angle -- the
/// an earlier version's approach -- does not hit the colors from the design.
enum AccentToken { blue, rust, violet, green, pink, ochre, teal, slate }

/// Background and text of a tag or avatar chip.
enum TagToken { red, blue, amber, violet, green, pink }

/// A color pair: a background and the text on it.
class ColorPair {
  const ColorPair(this.background, this.foreground);

  final Color background;
  final Color foreground;

  static ColorPair lerp(ColorPair a, ColorPair b, double t) => .new(
    Color.lerp(a.background, b.background, t) ?? a.background,
    Color.lerp(a.foreground, b.foreground, t) ?? a.foreground,
  );
}
