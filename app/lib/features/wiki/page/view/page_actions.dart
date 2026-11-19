import 'package:flutter/foundation.dart';

/// What the header of the screen around a page shows of it: whether it is being edited,
/// may be, is archived — and the three actions.
///
/// The page is laid under the area's own header, and "Edit" belongs in that header like
/// on a task or an event, not in a row of its own below it — at every width: beside the
/// tree the page used to draw a second, smaller title row with its own "Edit", a line
/// lower than everywhere else. The page owns the editing state, so it reports it here
/// and the header listens.
class PageActions extends ChangeNotifier {
  bool editing = false;
  bool writable = false;
  bool archived = false;
  VoidCallback? onEdit;
  VoidCallback? onDone;
  VoidCallback? onCancel;

  /// Called by the page after its build; only a change in what is shown rebuilds the
  /// header.
  void report({
    required bool editing,
    required bool writable,
    required bool archived,
    required VoidCallback onEdit,
    required VoidCallback onDone,
    required VoidCallback onCancel,
  }) {
    final changed =
        this.editing != editing ||
        this.writable != writable ||
        this.archived != archived;
    this.editing = editing;
    this.writable = writable;
    this.archived = archived;
    this.onEdit = onEdit;
    this.onDone = onDone;
    this.onCancel = onCancel;
    if (changed) notifyListeners();
  }

  /// The page is gone: nothing to show any more. Silent — the header that listened is
  /// being rebuilt without it anyway.
  void withdraw() {
    editing = false;
    writable = false;
    archived = false;
    onEdit = null;
    onDone = null;
    onCancel = null;
  }
}
