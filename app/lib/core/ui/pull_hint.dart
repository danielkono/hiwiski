import 'package:flutter/widgets.dart';

/// Whether the filter bars below show their hint ("Pull for filters"), and whom they
/// tell when a member pulled one down.
///
/// The hint teaches a gesture: once it is learned it only takes a line from the
/// content. The shell decides from the member's preferences (Account → Customize);
/// without a shell above (a screen on its own, in a test) the hint shows and nothing
/// is counted.
class PullHint extends InheritedWidget {
  const PullHint({
    super.key,
    required this.show,
    required this.onPulled,
    required super.child,
  });

  final bool show;

  /// A bar was pulled down while its hint was showing.
  final VoidCallback onPulled;

  /// Whether the hint shows below [context]; without a shell above, it does.
  static bool showsIn(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PullHint>()?.show ?? true;

  /// Tells the shell a bar below [context] was pulled down while its hint showed.
  static void pulledIn(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PullHint>()?.onPulled();

  @override
  bool updateShouldNotify(PullHint oldWidget) => show != oldWidget.show;
}
