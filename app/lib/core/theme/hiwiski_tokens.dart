import 'package:flutter/material.dart';

import 'hiwiski_accents.dart';
import 'hiwiski_metrics.dart';
import 'hiwiski_text_styles.dart';

/// Everything that has no place in `ColorScheme` and `TextTheme`.
///
/// Three pots, and every value belongs in exactly one: color roles in the
/// `ColorScheme`, text styles in the `TextTheme`, the rest here.
///
/// ```dart
/// final tokens = Theme.of(context).extension<HiwiskiTokens>()!;
/// ```
///
/// **No screen writes a color, a font size or a radius directly.** A
/// `Color(0xFF3B6939)` outside `core/theme/` is a bug; `test/theme_tokens_test.dart`
/// checks that there is none.
@immutable
class HiwiskiTokens extends ThemeExtension<HiwiskiTokens> {
  const HiwiskiTokens({
    required this.divider,
    required this.accents,
    required this.onAccent,
    required this.tags,
    required this.highlight,
    required this.code,
    required this.text,
    this.metrics = const HiwiskiMetrics(),
  });

  /// The row divider within a list.
  ///
  /// **Not `outlineVariant`.** The design uses two different values: `outlineVariant`
  /// for card borders, this one for row dividers. The divider is lighter.
  final Color divider;

  /// Calendars, lists, groups, members.
  final Map<AccentToken, Color> accents;

  /// The text on an accent surface — avatar initial, icon tile.
  ///
  /// One value per theme and not per accent: the light accents are saturated mid
  /// tones, the dark ones pastels. So in each theme exactly one ink works, and the
  /// contrast stays checked the same way across all eight.
  final Color onAccent;

  /// Tag and avatar colors, each a pair of background and text.
  final Map<TagToken, ColorPair> tags;

  /// The background a QR code sits on.
  ///
  /// **The same in both themes.** A QR code has to be dark on light, otherwise many
  /// cameras cannot read it — that is not a design question but a property of the
  /// code. That is why it lives here and not in the screen: a `Color(0xFFFFFFFF)` in
  /// the middle of a widget is exactly what `test/theme_discipline_test.dart`
  /// prevents.
  final ColorPair code;

  /// The background behind a search hit.
  ///
  /// It is drawn via `TextStyle.background` and not as a `WidgetSpan`, because a match
  /// in the middle of a sentence has to be able to wrap. The design's radius 3 is lost
  /// that way; at 14 px text nobody notices.
  final ColorPair highlight;

  final HiwiskiTextStyles text;

  final HiwiskiMetrics metrics;

  Color accent(AccentToken token) =>
      accents[token] ?? accents[AccentToken.slate]!;

  ColorPair tag(TagToken token) => tags[token] ?? tags[TagToken.blue]!;

  @override
  HiwiskiTokens copyWith({
    Color? divider,
    Map<AccentToken, Color>? accents,
    Color? onAccent,
    Map<TagToken, ColorPair>? tags,
    ColorPair? highlight,
    ColorPair? code,
    HiwiskiTextStyles? text,
    HiwiskiMetrics? metrics,
  }) => .new(
    divider: divider ?? this.divider,
    accents: accents ?? this.accents,
    onAccent: onAccent ?? this.onAccent,
    tags: tags ?? this.tags,
    highlight: highlight ?? this.highlight,
    code: code ?? this.code,
    text: text ?? this.text,
    metrics: metrics ?? this.metrics,
  );

  /// Without `lerp` the color jumps on a theme change instead of cross-fading.
  @override
  HiwiskiTokens lerp(ThemeExtension<HiwiskiTokens>? other, double t) {
    if (other is! HiwiskiTokens) return this;
    return HiwiskiTokens(
      divider: Color.lerp(divider, other.divider, t) ?? divider,
      accents: {
        for (final token in AccentToken.values)
          token:
              Color.lerp(accent(token), other.accent(token), t) ??
              accent(token),
      },
      onAccent: Color.lerp(onAccent, other.onAccent, t) ?? onAccent,
      tags: {
        for (final token in TagToken.values)
          token: ColorPair.lerp(tag(token), other.tag(token), t),
      },
      highlight: ColorPair.lerp(highlight, other.highlight, t),
      // **Do not** cross-fade: a QR code halfway between light and dark is unreadable
      // in both themes.
      code: other.code,
      text: text.lerp(other.text, t),
      metrics: other.metrics,
    );
  }
}

/// Shortcut to the tokens.
extension HiwiskiThemeAccess on BuildContext {
  HiwiskiTokens get tokens =>
      Theme.of(this).extension<HiwiskiTokens>() ??
      (throw StateError(
        'HiwiskiTheme registers HiwiskiTokens; this theme has none',
      ));

  ColorScheme get scheme => Theme.of(this).colorScheme;

  TextTheme get texts => Theme.of(this).textTheme;
}
