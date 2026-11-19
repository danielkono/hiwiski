import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Screens open and close at once, with no slide or zoom — on every platform. Only
/// on iOS the swipe back from the left edge moves the screen, under the finger: it
/// is the system's way back there, and without a screen to drag there would be no
/// gesture. Android has its own back gesture, and Safari on the Mac swipes back
/// through the browser's history; there the screen just goes.
///
/// For the swipe the iOS transition is used; it takes no time of its own, so a push
/// or a pop shows its end at once, while a swipe drives it by hand and a let-go swipe
/// finishes in its own short time.
class InstantPageTransitionsBuilder extends PageTransitionsBuilder {
  const InstantPageTransitionsBuilder({this.swipeBack = false});

  /// Whether a swipe from the left edge goes back.
  final bool swipeBack;

  @override
  Duration get transitionDuration => .zero;

  @override
  Duration get reverseTransitionDuration => .zero;

  @override
  // Flutter's transition API: the transition is built by a method.
  // ignore: many_lints/avoid_returning_widgets
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => swipeBack
      ? CupertinoRouteTransitionMixin.buildPageTransitions<T>(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        )
      : child;

  /// Every platform at once; iOS with the swipe back.
  static PageTransitionsTheme get theme => .new(
    builders: {
      for (final platform in TargetPlatform.values)
        platform: InstantPageTransitionsBuilder(swipeBack: platform == .iOS),
    },
  );
}
