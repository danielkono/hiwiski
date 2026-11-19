import 'package:flutter/widgets.dart';

/// A row whose title is edited right where it is — a task, a card: held, its
/// `RenamableTitle` turns into a field in place, without a dialog or a sheet over
/// the list. Enter or leaving the field saves, Escape keeps the old title.
///
/// Holding is the row's own long press; where a long press picks the row up
/// (`ItemDraggable` by touch), holding and letting go without moving it does.
class RenamableRow extends StatefulWidget {
  const RenamableRow({super.key, required this.onRenamed, required this.child});

  /// The title as entered — trimmed, not empty and not the old one. `null`: the
  /// title stays as it is (read only, a link's preview).
  final ValueChanged<String>? onRenamed;
  final Widget child;

  /// The row around [context], if its title can be edited.
  static RenamableRowState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<RenamableRowState>();

  /// Whether the row around [context] is being edited — and rebuilds [context]
  /// when that changes.
  static bool editing(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Editing>()?.editing ?? false;

  @override
  State<RenamableRow> createState() => RenamableRowState();
}

class RenamableRowState extends State<RenamableRow> {
  bool _editing = false;

  /// Opens the title as a field.
  void edit() {
    if (!_editing && widget.onRenamed != null) setState(() => _editing = true);
  }

  /// Closes the field — with the new [title], or `null` to keep the old one.
  void close(String? title) {
    if (!mounted) return;
    setState(() => _editing = false);
    if (title != null) widget.onRenamed?.call(title);
  }

  @override
  Widget build(BuildContext context) =>
      _Editing(editing: _editing, child: widget.child);
}

class _Editing extends InheritedWidget {
  const _Editing({required this.editing, required super.child});

  final bool editing;

  @override
  bool updateShouldNotify(_Editing oldWidget) => oldWidget.editing != editing;
}
