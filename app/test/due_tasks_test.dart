import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/domain/calendar/due_task.dart';
import 'package:hiwiski/domain/todo/todo_items.dart';

/// **Tasks with a due date show in the calendar** — on their day, open ones only, not
/// from an archived list, through the tag filter.
void main() {
  final from = DateTime(2026, 10, 19);
  final to = DateTime(2026, 10, 26);

  TodoList list(String id, {DateTime? archivedAt, String tags = ''}) => .new(
    id: id,
    ownerId: 'anna',
    version: 1,
    name: 'List $id',
    kind: ListKinds.standard,
    colorToken: 'blue',
    position: 0,
    assignees: '',
    tags: tags,
    archivedAt: archivedAt,
  );

  Todo todo(
    String id, {
    String listId = 'l1',
    DateTime? due,
    String status = TodoStatuses.open,
    String tags = '',
    String? time,
  }) => .new(
    id: id,
    ownerId: 'anna',
    version: 1,
    listId: listId,
    title: 'Task $id',
    status: status,
    dueDate: due,
    dueTime: time,
    assignees: '',
    tags: tags,
    position: 0,
  );

  test('an open task due in the window shows on its day, with its list', () {
    final byDay = dueTasksByDay(
      [
        todo('a', due: DateTime(2026, 10, 21)),
        todo('done', due: DateTime(2026, 10, 21), status: TodoStatuses.done),
        todo('none'),
        todo('later', due: DateTime(2026, 11, 2)),
        todo('archived', listId: 'l2', due: DateTime(2026, 10, 21)),
      ],
      [list('l1'), list('l2', archivedAt: DateTime(2026))],
      from: from,
      to: to,
      filter: const {},
    );
    expect(byDay.keys, equals([DateTime(2026, 10, 21)]));
    final task = byDay[DateTime(2026, 10, 21)]!.single;
    expect(task.todo.id, equals('a'));
    expect(task.listName, equals('List l1'));
  });

  test('a day sorts by due time, those without one first', () {
    final day = DateTime(2026, 10, 20);
    final byDay = dueTasksByDay(
      [
        todo('late', due: day, time: '18:00'),
        todo('any', due: day),
        todo('early', due: day, time: '08:00'),
      ],
      [list('l1')],
      from: from,
      to: to,
      filter: const {},
    );
    expect([
      for (final t in byDay[day]!) t.todo.id,
    ], equals(['any', 'early', 'late']));
  });

  test("the tag filter counts the task's tags and its list's", () {
    final day = DateTime(2026, 10, 20);
    final byDay = dueTasksByDay(
      [
        todo('tagged', due: day, tags: 'work'),
        todo('inList', listId: 'l2', due: day),
        todo('other', due: day),
      ],
      [list('l1'), list('l2', tags: 'work')],
      from: from,
      to: to,
      filter: const {'work'},
    );
    expect({
      for (final t in byDay[day]!) t.todo.id,
    }, equals({'tagged', 'inList'}));
  });
}
