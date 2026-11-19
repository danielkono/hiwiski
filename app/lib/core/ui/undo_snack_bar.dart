import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';

/// How long "Undo" is offered after a deletion, as the device has it (Account →
/// Customize). Set once above the app; the deletion itself waits a little longer
/// (`TodoRepository.deleteGrace`), so "Undo" works for as long as it shows.
class UndoWindow extends InheritedWidget {
  const UndoWindow({super.key, required this.duration, required super.child});

  /// Where nothing above says otherwise — a test, a screen on its own.
  static const fallback = Duration(seconds: 8);

  final Duration duration;

  static Duration of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UndoWindow>()?.duration ??
      fallback;

  @override
  bool updateShouldNotify(UndoWindow oldWidget) =>
      oldWidget.duration != duration;
}

/// [message] with "Undo" for the device's [UndoWindow] — then the note goes by
/// itself.
///
/// Not left standing: Flutter keeps a note with an action until it is dismissed, and
/// "Undo" tapped after the deletion went through did nothing — the rows stayed gone.
///
/// [onUndo] must not hang on the row that is gone by then: callers go through the
/// `ProviderContainer`, which outlives every screen.
void showUndoSnackBar(
  BuildContext context, {
  required String message,
  required VoidCallback onUndo,
}) {
  final l = L.of(context);
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: UndoWindow.of(context),
        persist: false,
        action: SnackBarAction(label: l.actionUndo, onPressed: onUndo),
      ),
    );
}
