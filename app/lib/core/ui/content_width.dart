import 'package:flutter/widgets.dart';

import '../shell/breakpoints.dart';

/// Measures the width a screen actually has — the window less the navigation beside
/// it, and in the wiki less the page tree — and gives it to everything below.
///
/// The width classes ([Breakpoint]) go by the window, which says nothing about what is
/// left once the drawer and the tree stand beside the content. Whatever has to fit
/// beside the content (the info bar) asks [ContentWidth.of] instead.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});

  final Widget child;

  /// The width of the area [context] lies in; without one measured above it (a screen
  /// on its own, in a test) the window's.
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Measured>()?.width ??
      MediaQuery.sizeOf(context).width;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _Measured(width: constraints.maxWidth, child: child),
  );
}

class _Measured extends InheritedWidget {
  const _Measured({required this.width, required super.child});

  final double width;

  @override
  bool updateShouldNotify(_Measured oldWidget) => width != oldWidget.width;
}
