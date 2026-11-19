import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_tokens.dart';

/// Whether this device types on a keyboard **on the screen** — phone and tablet.
///
/// There the keyboard covers the lower half: whatever belongs to typing (insert bar,
/// suggestions) docks on top of it instead of hanging next to the text. On the web the
/// platform is the one of the browser's device, so a phone's browser counts too.
bool typesOnScreen() =>
    defaultTargetPlatform == .iOS || defaultTargetPlatform == .android;

/// How far the keyboard on the screen reaches up from the bottom of the window.
///
/// Read from the view, not from the nearest [MediaQuery]: inside a [Scaffold]'s body
/// the insets are already taken off, and a list in the root overlay would not know
/// where the keyboard starts.
double keyboardHeightOf(BuildContext context) =>
    MediaQueryData.fromView(View.of(context)).viewInsets.bottom;

/// A strip docked right above the keyboard — the full width, a line on top.
///
/// Its height is fixed ([height]), so whatever docks above it (the suggestions for
/// `#…`) knows where to sit.
class KeyboardBar extends StatelessWidget {
  const KeyboardBar({super.key, required this.child});

  /// The tap target plus the line on top.
  static const double height =
      HiwiskiMetrics.minTapTarget + HiwiskiMetrics.hairline;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.scheme.surfaceContainer,
        // The context is BoxBorder: abstract, a shorthand finds no constructor.
        // ignore: many_lints/prefer_shorthands_with_constructors
        border: Border(top: BorderSide(color: context.scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(height: height - HiwiskiMetrics.hairline, child: child),
      ),
    );
  }
}
