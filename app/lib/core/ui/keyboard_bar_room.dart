import 'package:flutter/widgets.dart';

/// Leaves room above the keyboard for what the browser lays over it.
///
/// [overlap] is how much of the page above the keyboard the browser covers — Safari's
/// floating bar on the iPhone (`keyboardBarOverlap`). While the keyboard is open, it
/// counts as keyboard: what is docked above the keyboard comes to rest above the bar.
class KeyboardBarRoom extends StatelessWidget {
  const KeyboardBarRoom({
    super.key,
    required this.overlap,
    required this.child,
  });

  final double overlap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    if (overlap == 0 || insets.bottom == 0) return child;
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(viewInsets: insets.copyWith(bottom: insets.bottom + overlap)),
      child: child,
    );
  }
}
