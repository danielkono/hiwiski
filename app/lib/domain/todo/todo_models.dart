import 'todo_items.dart';
import '../../core/common/wire.dart';

/// A list with its numbers — the way the overview shows it.
class TodoListSummary {
  const TodoListSummary({
    required this.list,
    required this.open,
    required this.done,
  });

  final TodoList list;
  final int open;
  final int done;

  bool get isShopping => list.kind == ListKinds.shopping;

  int get total => open + done;

  /// For the progress bar. An empty list sits at 0, not at 1 — otherwise
  /// "nothing in it yet" would look like "all done".
  double get progress => total == 0 ? 0 : done / total;
}

/// Where a shopping row dropped on [onRow] (or, without one, at the end) goes: the
/// rows it is ordered among — only those of its own status, itself left out — and its
/// index there.
///
/// Open and done rows are each ordered by position on their own. Counted among both,
/// the neighbours were not neighbours: a drop after a done row put an open one above
/// the first open row, and between an open and a done row everything, done rows
/// included, was renumbered. On a row of the other status an open row goes to the end
/// of the open ones, a done row to the start of the done ones.
///
/// Without [byStatus] — a task list on a device that keeps done rows where they were —
/// all rows are one order, and the row goes right where it was dropped.
({List<Todo> others, int at}) dropPlace(
  Todo todo, {
  required List<Todo> rows,
  Todo? onRow,
  bool before = true,
  bool byStatus = true,
}) {
  final others = [
    for (final row in rows)
      if (row.id != todo.id && (!byStatus || row.status == todo.status)) row,
  ];
  final at = switch (onRow) {
    null => others.length,
    _ when !byStatus || onRow.status == todo.status =>
      others.indexWhere((row) => row.id == onRow.id) + (before ? 0 : 1),
    _ => todo.status == TodoStatuses.done ? 0 : others.length,
  };
  return (others: others, at: at);
}
