import 'package:flutter/material.dart';

/// The two color sets from the design.
///
/// Light and dark are **fixed token sets, not derived from a seed**: a generated
/// scheme is a different one with every Flutter update, and a design worked out down
/// to the hex values does not get better through an algorithm.
///
/// The design names 16 colors, `ColorScheme` requires 30. The gap is closed here and
/// not left to the framework -- otherwise Flutter fills in defaults that fall outside
/// the design.
abstract final class HiwiskiColorSchemes {
  static const ColorScheme light = ColorScheme(
    brightness: .light,

    // --- From the design ---
    surface: Color(0xFFF8FAF0), // bg
    surfaceContainerLow: Color(0xFFF2F5EA), // sf1
    surfaceContainer: Color(0xFFECEFE4), // sf2
    surfaceContainerHigh: Color(0xFFE6E9DF), // sf3
    onSurface: Color(0xFF191D17), // on
    onSurfaceVariant: Color(0xFF424940), // onv
    outline: Color(0xFF72796F), // outl
    outlineVariant: Color(0xFFC2C8BD), // outlv
    primary: Color(0xFF3B6939), // pri
    onPrimary: Color(0xFFFFFFFF), // onpri
    primaryContainer: Color(0xFFBCF0B4), // pc
    onPrimaryContainer: Color(0xFF002204), // onpc
    // `sec` is secondaryContainer, not secondary: in the design it is always a
    // background with text on it -- selected chip, navigation pill, active tree row.
    // That is exactly what NavigationBar, FilterChip and NavigationDrawer reach for.
    secondaryContainer: Color(0xFFD7E8CD), // sec
    onSecondaryContainer: Color(0xFF111F0F), // onsec
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),

    // --- Filled in, because Flutter would otherwise invent them ---
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerHighest: Color(0xFFE0E4DA),
    // Only for outlines and icons, never as a surface.
    secondary: Color(0xFF52634F),
    onSecondary: Color(0xFFFFFFFF),
    // Not used in the design; set so that nothing foreign shows up.
    tertiary: Color(0xFF38656A),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFBCEBF0),
    onTertiaryContainer: Color(0xFF002023),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    // SnackBar.
    inverseSurface: Color(0xFF2E322C),
    onInverseSurface: Color(0xFFEFF2E8),
    inversePrimary: Color(0xFFA1D39A),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    // Material 3 lays a `primary` tint over the surface at every elevation -- and when
    // scrolling under the AppBar. Then the hex values above would no longer be right
    // (pitfall 1).
    surfaceTint: Colors.transparent,
  );

  static const ColorScheme dark = ColorScheme(
    brightness: .dark,

    // --- From the design ---
    surface: Color(0xFF10140F),
    surfaceContainerLow: Color(0xFF1D211B),
    surfaceContainer: Color(0xFF272B25),
    surfaceContainerHigh: Color(0xFF32362F),
    onSurface: Color(0xFFE0E4DA),
    onSurfaceVariant: Color(0xFFC2C8BD),
    outline: Color(0xFF8C9388),
    outlineVariant: Color(0xFF424940),
    primary: Color(0xFFA1D39A),
    onPrimary: Color(0xFF0A390F),
    primaryContainer: Color(0xFF235024),
    onPrimaryContainer: Color(0xFFBCF0B4),
    secondaryContainer: Color(0xFF3B4B38),
    onSecondaryContainer: Color(0xFFD7E8CD),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),

    // --- Filled in ---
    surfaceContainerLowest: Color(0xFF0B0F0A),
    surfaceContainerHighest: Color(0xFF3D413A),
    secondary: Color(0xFFB9CCB4),
    onSecondary: Color(0xFF243424),
    tertiary: Color(0xFFA0CFD4),
    onTertiary: Color(0xFF00363A),
    tertiaryContainer: Color(0xFF1F4D51),
    onTertiaryContainer: Color(0xFFBCEBF0),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    inverseSurface: Color(0xFFE0E4DA),
    onInverseSurface: Color(0xFF2E322C),
    inversePrimary: Color(0xFF3B6939),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Colors.transparent,
  );
}
