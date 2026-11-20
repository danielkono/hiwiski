import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether the Scaffold shows [button] at full size, upright and opaque.
///
/// When a Scaffold gets a floating button after it was first built, it scales,
/// fades or rotates the button in. In the first frame that transition is still
/// at its start, so a frame pumped without time passing catches it. Only the
/// transitions between the Scaffold and the button count: the route's own
/// transitions above the Scaffold are not the button's.
bool shownInFull(WidgetTester tester, Finder button) {
  final transitions = find.descendant(
    of: find.byType(Scaffold),
    matching: find.ancestor(
      of: button,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is ScaleTransition ||
            widget is FadeTransition ||
            widget is RotationTransition,
      ),
    ),
  );
  return tester
      .widgetList(transitions)
      .map(
        (widget) => switch (widget) {
          ScaleTransition(:final scale) => scale.value,
          FadeTransition(:final opacity) => opacity.value,
          RotationTransition(:final turns) => turns.value,
          _ => throw StateError('Not a transition: $widget'),
        },
      )
      .every((value) => value == 1);
}
