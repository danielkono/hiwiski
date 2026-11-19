import 'package:flutter/widgets.dart';

/// Marks a screen shown **inside another screen** — a list open next to the overview's
/// rows. The outer screen already has the header's avatar and the sync banner; the
/// inner one leaves them out, and its back arrow with them: there is nowhere to go
/// back to inside the same page.
class EmbeddedPage extends InheritedWidget {
  const EmbeddedPage({super.key, required super.child});

  /// Whether [context] sits inside an embedded screen.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EmbeddedPage>() != null;

  @override
  bool updateShouldNotify(EmbeddedPage oldWidget) => false;
}
