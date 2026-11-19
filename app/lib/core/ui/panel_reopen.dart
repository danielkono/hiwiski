import 'package:flutter/widgets.dart';

import '../theme/hiwiski_metrics.dart';

/// The button that brings back a side panel put away — the wiki's tree, the task
/// lists' rows — handed to the screen beside it, which shows it left of its title.
///
/// It used to stand in a column of its own along the whole height: the panel was
/// gone, and its room was not.
///
/// **It stands where the button that put the panel away stood**: both are the first
/// thing in the first row below the area's header, [inset] from the left edge. Whoever
/// closes the panel opens it again without moving the pointer.
class PanelReopen extends InheritedWidget {
  const PanelReopen({super.key, required this.button, required super.child});

  /// How far the button's box stands from the left edge, with the panel and without:
  /// the symbol in it then stands on the page's margin, in line with the text below.
  static const double inset = HiwiskiMetrics.space20;

  /// `null` while the panel shows.
  final Widget? button;

  /// The button to show left of the title, if a panel beside was put away.
  // The button is what is handed down; a widget is what there is to hand.
  // ignore: many_lints/avoid_returning_widgets
  static Widget? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PanelReopen>()?.button;

  @override
  bool updateShouldNotify(PanelReopen oldWidget) => button != oldWidget.button;
}
