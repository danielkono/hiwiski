import '../../core/api/generated/export.dart';
import '../../core/common/wire.dart';
import '../access/access_rules.dart';
import '../tags/tag.dart';
import 'todo_items.dart';

// What a list allows its reader — the same for a checklist, a shopping list and a
// board. The reader's level is *write*, *check off* or *read*; `null`
// while unknown.

/// An archived list is read-only, its tasks with it: no quick entry, no
/// ticking, no renaming. Restoring and deleting stay with whoever may write
/// ([mayWrite]).
bool listWritable(TodoList list, AccessLevel? level) =>
    mayWrite(level) && list.archivedAt == null;

/// Deleting the list is its owner's ([ownsItem]); archiving stays with whoever may
/// write ([mayWrite]).
bool mayDeleteList(TodoList list, AccessLevel? level, String? me) =>
    mayWrite(level) && ownsItem(list.ownerId, me);

/// Whether [todo]'s box can be ticked: *check off* on the list, or assigned to [me].
bool mayCheckOff(
  TodoList list,
  Todo todo, {
  required AccessLevel? level,
  required String? me,
}) =>
    list.archivedAt == null &&
    (mayCheck(level) || (me != null && tagIdsOf(todo.assignees).contains(me)));

/// The entries ticked off — what "Delete ticked-off" and "Untick all" touch.
List<Todo> doneItems(List<Todo> items) => [
  for (final todo in items)
    if (todo.status == TodoStatuses.done) todo,
];

/// The entries not done yet.
int openCount(List<Todo> items) =>
    items.where((todo) => todo.status != TodoStatuses.done).length;
