import 'package:hiwiski/core/theme/hiwiski_accents.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/core/theme/hiwiski_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The design tokens, measured again.
///
/// The design is worked out down to the hex values; a typo in it would otherwise only
/// show up when someone puts two screens side by side.
void main() {
  group('ColorScheme', () {
    test('light carries the values from the design', () {
      final scheme = HiwiskiTheme.light().colorScheme;
      expect(scheme.surface, equals(const Color(0xFFF8FAF0)));
      expect(scheme.surfaceContainer, equals(const Color(0xFFECEFE4)));
      expect(scheme.primary, equals(const Color(0xFF3B6939)));
      expect(scheme.onSurface, equals(const Color(0xFF191D17)));
      // `sec` is secondaryContainer, not secondary.
      expect(scheme.secondaryContainer, equals(const Color(0xFFD7E8CD)));
      expect(scheme.error, equals(const Color(0xFFB3261E)));
    });

    test('dark carries the values from the design', () {
      final scheme = HiwiskiTheme.dark().colorScheme;
      expect(scheme.surface, equals(const Color(0xFF10140F)));
      expect(scheme.primary, equals(const Color(0xFFA1D39A)));
      expect(scheme.secondaryContainer, equals(const Color(0xFF3B4B38)));
    });

    test('surfaceTint is turned off, otherwise the hex values no longer match', () {
      // Material 3 lays a tint of `primary` over the surface at every elevation
      // (pitfall 1).
      for (final theme in [HiwiskiTheme.light(), HiwiskiTheme.dark()]) {
        expect(theme.colorScheme.surfaceTint, equals(Colors.transparent));
        expect(theme.cardTheme.surfaceTintColor, equals(Colors.transparent));
        expect(theme.appBarTheme.surfaceTintColor, equals(Colors.transparent));
        expect(theme.appBarTheme.scrolledUnderElevation, equals(0));
        expect(theme.dialogTheme.surfaceTintColor, equals(Colors.transparent));
        expect(
          theme.bottomSheetTheme.surfaceTintColor,
          equals(Colors.transparent),
        );
        expect(
          theme.popupMenuTheme.surfaceTintColor,
          equals(Colors.transparent),
        );
      }
    });
  });

  group('HiwiskiTokens', () {
    test('the row divider is lighter than outlineVariant', () {
      final light = HiwiskiTheme.light();
      final tokens = light.extension<HiwiskiTokens>()!;
      expect(tokens.divider, equals(const Color(0xFFDDE3D6)));
      expect(tokens.divider, isNot(light.colorScheme.outlineVariant));
      // So that `Divider` and `ListTile` are right on their own.
      expect(light.dividerTheme.color, equals(tokens.divider));
    });

    test('all eight accents are set in both themes', () {
      for (final theme in [HiwiskiTheme.light(), HiwiskiTheme.dark()]) {
        final tokens = theme.extension<HiwiskiTokens>()!;
        for (final token in AccentToken.values) {
          expect(tokens.accents[token], isNotNull, reason: '$token is missing');
        }
      }
    });

    test('all six tag pairs are set in both themes', () {
      // The design only shows them light; the dark column closes this gap.
      final light = HiwiskiTheme.light().extension<HiwiskiTokens>()!;
      final dark = HiwiskiTheme.dark().extension<HiwiskiTokens>()!;
      for (final token in TagToken.values) {
        expect(light.tags[token], isNotNull, reason: '$token light is missing');
        expect(dark.tags[token], isNotNull, reason: '$token dark is missing');
        expect(
          light.tags[token]!.background,
          isNot(dark.tags[token]!.background),
          reason:
              '$token is the same in both themes -- that was the gap in the design',
        );
      }
    });

    test('lerp blends instead of jumping', () {
      final light = HiwiskiTheme.light().extension<HiwiskiTokens>()!;
      final dark = HiwiskiTheme.dark().extension<HiwiskiTokens>()!;
      final middle = light.lerp(dark, 0.5);
      expect(middle.divider, isNot(light.divider));
      expect(middle.divider, isNot(dark.divider));
      expect(
        middle.accent(AccentToken.blue),
        isNot(light.accent(AccentToken.blue)),
      );
    });
  });

  group('typography', () {
    test('the sizes and weights are as in the design', () {
      final texts = HiwiskiTheme.light().textTheme;
      expect(texts.headlineLarge!.fontSize, equals(30));
      expect(texts.headlineMedium!.fontSize, equals(26));
      expect(texts.titleLarge!.fontSize, equals(22));
      expect(texts.bodyLarge!.fontSize, equals(16));
      expect(texts.bodyLarge!.fontWeight, equals(FontWeight.w500));
      expect(texts.bodySmall!.fontSize, equals(13));
      expect(texts.labelSmall!.fontSize, equals(11));
    });

    test('every weight also sets the wght axis', () {
      // Roboto is in the repository as a variable font. Without `fontVariations` it
      // stays at 400 on some platforms -- without any error message.
      final texts = HiwiskiTheme.light().textTheme;
      for (final style in [
        texts.headlineLarge!,
        texts.titleLarge!,
        texts.bodyLarge!,
        texts.labelLarge!,
      ]) {
        final wght = style.fontVariations?.firstWhere((v) => v.axis == 'wght');
        expect(wght, isNotNull, reason: 'fontVariations is missing on $style');
        expect(wght!.value, equals(style.fontWeight!.value.toDouble()));
      }
    });

    test('mono only where something gets copied by hand', () {
      final tokens = HiwiskiTheme.light().extension<HiwiskiTokens>()!;
      expect(tokens.text.entityKey.fontFamily, equals('RobotoMono'));
      expect(tokens.text.monoSmall.fontFamily, equals('RobotoMono'));
      expect(tokens.text.inviteCode.fontFamily, equals('RobotoMono'));
      expect(tokens.text.inviteCode.letterSpacing, equals(3));
      // Body text is no exception to that.
      expect(tokens.text.prose.fontFamily, equals('Roboto'));
      expect(tokens.text.prose.height, equals(1.6));
    });
  });
}
