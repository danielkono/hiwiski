import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'page_background.dart';

/// The operating system's bars follow the page instead of drawing their own colour.
///
/// - **Android:** status and navigation bar are transparent, the app draws behind them
///   (edge to edge, as Android 15 enforces anyway); only the icons switch between
///   light and dark. No contrast scrim — the surface behind is calm enough.
/// - **iOS:** the status bar is transparent anyway; `statusBarBrightness` picks the
///   icon colour.
/// - **Web:** Safari and Chrome tint their address and status bar from `theme-color`
///   and the page background. Both follow the surface of the theme in use — also when
///   the member chose a theme other than the system's.
class SystemBars extends StatelessWidget {
  const SystemBars({super.key, required this.child});

  final Widget child;

  /// Once before the first frame: otherwise Android before 15 keeps reserving the
  /// space for opaque bars.
  static Future<void> enableEdgeToEdge() =>
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  static SystemUiOverlayStyle styleFor(ColorScheme scheme) {
    final dark = scheme.brightness == .dark;
    final icons = dark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: icons,
      // iOS names the *background*, not the icons.
      statusBarBrightness: scheme.brightness,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: icons,
      systemNavigationBarContrastEnforced: false,
    );
  }

  /// The page background last written — there is one page. Written on every build,
  /// a theme cross-fade wrote the DOM on every frame.
  static Color? _background;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (scheme.surface != _background) {
      _background = scheme.surface;
      setPageBackground(scheme.surface);
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: styleFor(scheme),
      child: child,
    );
  }
}
