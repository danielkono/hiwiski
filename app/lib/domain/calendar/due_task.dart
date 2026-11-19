import '../../core/common/wire.dart';
import '../common/calendar_days.dart';
import '../tags/tag.dart';
import '../todo/todo_items.dart';

/// A task with a due date as the calendar shows it: on its day, marked as a task —
/// a box, not a color bar — and named with its list.
class const DueTask({
  required final Todo todo,

  /// The list's name, so "Regal bauen · Haus" says where it belongs.
  required final String listName,

  /// The day it is due.
  required final DateTime day,
}) {
  bool get done => todo.status == TodoStatuses.done;
}

/// The tasks the calendar shows in `[from, to)`, by day: due in the window, not done,
/// not in an archived list, through the tag filter — a list's tags count for its
/// tasks. Within a day by due time, those without one first.
Map<DateTime, List<DueTask>> dueTasksByDay(
  List<Todo> todos,
  List<TodoList> lists, {
  required DateTime from,
  required DateTime to,
  required Set<String> filter,
}) {
  final byId = {for (final list in lists) list.id: list};
  final byDay = <DateTime, List<DueTask>>{};
  for (final todo in todos) {
    final due = todo.dueDate;
    final list = byId[todo.listId];
    if (due == null ||
        list == null ||
        list.archivedAt != null ||
        todo.status == TodoStatuses.done) {
      continue;
    }
    final day = startOfDay(due);
    if (day.isBefore(from) || !day.isBefore(to)) continue;
    if (!passesTagFilter(filter, '${todo.tags},${list.tags}')) continue;
    byDay
        .putIfAbsent(day, () => [])
        .add(DueTask(todo: todo, listName: list.name, day: day));
  }
  for (final tasks in byDay.values) {
    tasks.sort(
      (a, b) => (a.todo.dueTime ?? '').compareTo(b.todo.dueTime ?? ''),
    );
  }
  return byDay;
}
