import 'package:flutter/material.dart';

import 'hiwiski_accents.dart';
import 'hiwiski_color_schemes.dart';
import 'hiwiski_metrics.dart';
import 'hiwiski_text_styles.dart';
import 'hiwiski_tokens.dart';
import 'instant_page_transitions.dart';

/// Builds the two themes from the tokens in `hiwiski_tokens.dart`.
///
/// Everything a Material widget uses on its own lives here in `ColorScheme`,
/// `TextTheme` or a widget theme. What has no place there lives in
/// [HiwiskiTokens].
/// A style at another weight, the way the theme sets every weight: `fontWeight` and
/// the `wght` axis of the variable font together (see [HiwiskiTheme]).
extension HiwiskiWeight on TextStyle {
  TextStyle withWeight(FontWeight weight) => copyWith(
    fontWeight: weight,
    fontVariations: [
      FontVariation(HiwiskiTheme._weightAxis, weight.value.toDouble()),
    ],
  );
}

abstract final class HiwiskiTheme {
  static const String _sans = 'Roboto';

  /// Mono exclusively for readable keys, addresses and the invitation code --
  /// it is not decoration but says "you can copy this down".
  static const String _mono = 'RobotoMono';
  static const String _weightAxis = 'wght';

  static ThemeData light() => _build(HiwiskiColorSchemes.light, _lightTokens);

  static ThemeData dark() => _build(HiwiskiColorSchemes.dark, _darkTokens);

  // ---------------------------------------------------------------------------
  // Font
  // ---------------------------------------------------------------------------

  /// Roboto and Roboto Mono live in the repository as **variable** fonts -- Google
  /// no longer ships them any other way.
  ///
  /// That is why the weight is set twice: `fontWeight` for Flutter's selection and
  /// `fontVariations` for the `wght` axis. Without the axis the font stays at 400 on
  /// some platforms, and without any error message.
  static TextStyle _style(
    double size,
    FontWeight weight, {
    String family = _sans,
    double? height,
    double? letterSpacing,
    Color? color,
  }) => .new(
    fontFamily: family,
    fontSize: size,
    fontWeight: weight,
    fontVariations: [FontVariation(_weightAxis, weight.value.toDouble())],
    height: height,
    letterSpacing: letterSpacing,
    color: color,
  );

  /// The roles Material widgets pick up on their own. `displayLarge/Medium/Small` are not used and stay at
  /// Flutter's default.
  static TextTheme _textTheme(ColorScheme scheme) => TextTheme(
    headlineLarge: _style(30, FontWeight.w600), // page title, desktop
    headlineMedium: _style(26, FontWeight.w600), // page title, phone
    headlineSmall: _style(24, FontWeight.w600), // item title in detail
    titleLarge: _style(22, FontWeight.w600), // sheet and dialog title
    titleMedium: _style(20, FontWeight.w600), // subpage title, phone
    titleSmall: _style(16, FontWeight.w600), // card title
    bodyLarge: _style(16, FontWeight.w500), // list row
    bodyMedium: _style(14, FontWeight.w400), // secondary text
    bodySmall: _style(13, FontWeight.w400), // meta, hints
    labelLarge: _style(14, FontWeight.w500), // button, chip
    labelMedium: _style(12, FontWeight.w400), // field label
    labelSmall: _style(11, FontWeight.w400), // smallest
  ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

  static HiwiskiTextStyles _styles(ColorScheme scheme) => .new(
    sectionLabel: _style(14, FontWeight.w600, color: scheme.primary),
    // In Flutter `height` is a factor of the font size, like a unitless
    // `line-height` in CSS.
    prose: _style(16, FontWeight.w400, height: 1.6, color: scheme.onSurface),
    shoppingLine: _style(17, FontWeight.w400, color: scheme.onSurface),
    shoppingAmount: _style(17, FontWeight.w600, color: scheme.onSurface),
    entityKey: _style(
      11,
      FontWeight.w400,
      family: _mono,
      color: scheme.onSurfaceVariant,
    ),
    monoSmall: _style(
      13,
      FontWeight.w400,
      family: _mono,
      color: scheme.onSurfaceVariant,
    ),
    inviteCode: _style(
      26,
      FontWeight.w500,
      family: _mono,
      letterSpacing: 3,
      color: scheme.onSurface,
    ),
    cardTitle: _style(17, FontWeight.w600, color: scheme.onSurface),
    accountName: _style(18, FontWeight.w600, color: scheme.onSurface),
  );

  // ---------------------------------------------------------------------------
  // Tokens
  // ---------------------------------------------------------------------------

  static HiwiskiTokens get _lightTokens => .new(
    // Not `outlineVariant`: the design uses two values -- `outlv` for card
    // borders, `div` for row dividers. The divider is lighter.
    divider: const Color(0xFFDDE3D6),
    onAccent: const Color(0xFFFFFFFF),
    accents: const {
      .blue: Color(0xFF1F6FB2),
      .rust: Color(0xFFB3541E),
      .violet: Color(0xFF7B4FA8),
      .green: Color(0xFF2E7D5B),
      .pink: Color(0xFFC2185B),
      .ochre: Color(0xFF8D6E00),
      .teal: Color(0xFF00696D),
      .slate: Color(0xFF5F6368),
    },
    tags: const {
      .red: ColorPair(Color(0xFFFFDAD6), Color(0xFF410002)),
      .blue: ColorPair(Color(0xFFD3E4FF), Color(0xFF001C38)),
      .amber: ColorPair(Color(0xFFFFDDB3), Color(0xFF291800)),
      .violet: ColorPair(Color(0xFFE8DEF8), Color(0xFF1D192B)),
      .green: ColorPair(Color(0xFFC4EED0), Color(0xFF00210F)),
      .pink: ColorPair(Color(0xFFFFD8E4), Color(0xFF31111D)),
    },
    highlight: const ColorPair(Color(0xFFFFDDB3), Color(0xFF291800)),
    // A QR code has to be dark on light -- in both themes. Otherwise many
    // cameras cannot read it.
    code: const ColorPair(Color(0xFFFFFFFF), Color(0xFF000000)),
    text: _styles(HiwiskiColorSchemes.light),
  );

  static HiwiskiTokens get _darkTokens => .new(
    divider: const Color(0xFF2C302A),
    onAccent: const Color(0xFF10140F),
    // The light values are as in the design, the dark ones are derived and
    // signed off.
    accents: const {
      .blue: Color(0xFF8FC7F5),
      .rust: Color(0xFFFFB68C),
      .violet: Color(0xFFD5BAFF),
      .green: Color(0xFF8ADCB4),
      .pink: Color(0xFFFFB0C8),
      .ochre: Color(0xFFE5C44C),
      .teal: Color(0xFF80D4D8),
      .slate: Color(0xFFC4C7C5),
    },
    // The design shows these pairs only in light and keeps them unchanged in
    // the dark theme -- there pastel chips glared out of an almost black
    // background. That is a gap in the design, not intent; this column closes
    // it.
    tags: const {
      .red: ColorPair(Color(0xFF93000A), Color(0xFFFFDAD6)),
      .blue: ColorPair(Color(0xFF00497D), Color(0xFFD3E4FF)),
      .amber: ColorPair(Color(0xFF6B4E00), Color(0xFFFFDDB3)),
      .violet: ColorPair(Color(0xFF4A4458), Color(0xFFE8DEF8)),
      .green: ColorPair(Color(0xFF00522C), Color(0xFFC4EED0)),
      .pink: ColorPair(Color(0xFF7D2949), Color(0xFFFFD8E4)),
    },
    highlight: const ColorPair(Color(0xFF6B4E00), Color(0xFFFFDDB3)),
    // A QR code has to be dark on light -- in both themes. Otherwise many
    // cameras cannot read it.
    code: const ColorPair(Color(0xFFFFFFFF), Color(0xFF000000)),
    text: _styles(HiwiskiColorSchemes.dark),
  );

  // ---------------------------------------------------------------------------
  // The theme
  // ---------------------------------------------------------------------------

  static ThemeData _build(ColorScheme scheme, HiwiskiTokens tokens) {
    final texts = _textTheme(scheme);

    return ThemeData(
      colorScheme: scheme,
      textTheme: texts,
      fontFamily: _sans,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      // Screens open at once; only the swipe back moves one.
      pageTransitionsTheme: InstantPageTransitionsBuilder.theme,
      extensions: [tokens],

      // `VisualDensity.standard`, not `adaptivePlatformDensity`: the adaptive
      // variant shrinks on desktop platforms and so undercuts the target sizes from
      // the design (pitfall 2).
      visualDensity: .standard,
      materialTapTargetSize: .padded,

      // There is hardly any elevation. Cards are flat with an outline instead of a
      // shadow; shadows only for things that really lie on top.
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: texts.titleLarge,
        iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
      ),

      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      // So that `Divider` and `ListTile` are right on their own.
      dividerTheme: DividerThemeData(
        color: tokens.divider,
        space: 1,
        thickness: 1,
      ),
      dividerColor: tokens.divider,

      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        // Text fields are almost square at 6 -- that separates "you type here" from
        // "you read here".
        border: OutlineInputBorder(
          borderRadius: const .all(.circular(HiwiskiMetrics.radiusField)),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const .all(.circular(HiwiskiMetrics.radiusField)),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const .all(.circular(HiwiskiMetrics.radiusField)),
          borderSide: BorderSide(width: 2, color: scheme.primary),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: const .all(.circular(HiwiskiMetrics.radiusField)),
          borderSide: BorderSide(color: scheme.error),
        ),
        // No fixed height: text sizes scale via `MediaQuery.textScaler`, and a
        // `SizedBox(height:)` around text clips with a large system font
        // (pitfall 3).
        contentPadding: const .symmetric(
          horizontal: HiwiskiMetrics.space12,
          vertical: HiwiskiMetrics.space16,
        ),
        labelStyle: texts.labelMedium,
        hintStyle: texts.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: .vertical(top: .circular(HiwiskiMetrics.radiusSheet)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: const RoundedRectangleBorder(
          borderRadius: .all(.circular(HiwiskiMetrics.radiusSheet)),
        ),
        titleTextStyle: texts.titleLarge,
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: const RoundedRectangleBorder(
          borderRadius: .all(.circular(HiwiskiMetrics.radiusMenu)),
        ),
        textStyle: texts.bodyLarge,
      ),

      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(3),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: .all(.circular(HiwiskiMetrics.radiusMenu)),
            ),
          ),
        ),
      ),

      // No `StadiumBorder`: chips have radius 8 in the design.
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        selectedColor: scheme.secondaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: texts.labelLarge,
        padding: const .symmetric(
          horizontal: HiwiskiMetrics.space12,
          vertical: HiwiskiMetrics.space6,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: .all(.circular(HiwiskiMetrics.radiusChip)),
        ),
        showCheckmark: false,
      ),

      // `FloatingActionButton.extended` is otherwise a `StadiumBorder` in Material 3 --
      // so the radius has to be set.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        elevation: 3,
        focusElevation: 3,
        hoverElevation: 3,
        highlightElevation: 3,
        extendedTextStyle: texts.labelLarge,
        shape: const RoundedRectangleBorder(
          borderRadius: .all(.circular(HiwiskiMetrics.radiusCard)),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        labelBehavior: .alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(texts.labelMedium),
        height: 80,
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        // Flutter's default is 72.
        minWidth: HiwiskiMetrics.railWidth,
        labelType: .all,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        elevation: 0,
      ),

      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // Flutter's default is 360, which is too wide.
        tileHeight: 52,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: .all(.circular(26)),
        ),
        indicatorSize: const Size.fromHeight(52),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
          foregroundColor: scheme.onSurfaceVariant,
        ),
      ),

      // `FILL 0` at rest. `FILL 1` is set at the call site and is the only state
      // indicator on a symbol in the whole design.
      iconTheme: IconThemeData(
        color: scheme.onSurfaceVariant,
        size: 24,
        fill: 0,
        weight: 400,
        grade: 0,
        opticalSize: 24,
      ),

      listTileTheme: ListTileThemeData(
        titleTextStyle: texts.bodyLarge,
        subtitleTextStyle: texts.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        iconColor: scheme.onSurfaceVariant,
        minVerticalPadding: HiwiskiMetrics.space8,
      ),

      // Pill button, height via `minimumSize`.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          minimumSize: const Size(0, 44),
          textStyle: texts.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          minimumSize: const Size(0, 44),
          side: BorderSide(color: scheme.outline),
          textStyle: texts.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const StadiumBorder(),
          minimumSize: const Size(0, 44),
          textStyle: texts.labelLarge,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: texts.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        behavior: .floating,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        linearMinHeight: HiwiskiMetrics.progressStripHeight,
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHigh,
      ),

      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(borderRadius: .all(.circular(4))),
        side: BorderSide(color: scheme.outline, width: 2),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
        ),
        textStyle: texts.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
    );
  }
}
