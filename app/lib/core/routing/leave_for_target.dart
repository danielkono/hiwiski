import 'package:flutter/widgets.dart';

/// A screen outside the app's frame — a pinboard full screen — that makes way before
/// a link's target opens: the target opens in the frame, and the frame lies under the
/// screen. Opened there, the target appeared behind the map, out of sight.
class LeaveForTarget extends InheritedWidget {
  const LeaveForTarget({super.key, required this.leave, required super.child});

  /// Closes the screen.
  final VoidCallback leave;

  /// The way out of the screen [context] is in — `null` in the app's frame.
  static VoidCallback? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LeaveForTarget>()?.leave;

  @override
  bool updateShouldNotify(LeaveForTarget oldWidget) => oldWidget.leave != leave;
}
