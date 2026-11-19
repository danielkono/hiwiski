import 'package:flutter/widgets.dart';

/// A view of the app embedded in the website as a scene: the screen alone, without the shell around it — no navigation bar, no
/// rail, no way into the rest of the app.
class SceneFrame extends InheritedWidget {
  const SceneFrame({super.key, required super.child});

  /// Whether [context] lies inside a scene.
  static bool isScene(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SceneFrame>() != null;

  @override
  bool updateShouldNotify(SceneFrame oldWidget) => false;
}
