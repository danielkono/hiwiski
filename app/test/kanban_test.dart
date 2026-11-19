import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/todo/kanban.dart';
import 'package:hiwiski/domain/todo/todo_items.dart';

/// **Where a card stands is derived** (Kanban) — and what a change
/// of the columns does to the cards.
void main() {
  const todo = KanbanColumn(id: 'todo', name: 'To do');
  const doing = KanbanColumn(id: 'doing', name: 'Doing');
  const done = KanbanColumn(id: 'done', name: 'Done', done: true);
  const columns = [todo, doing, done];

  Todo card(
    String id, {
    String status = 'OPEN',
    String? column,
    int position = 0,
  }) => .new(
    id: id,
    ownerId: 'anna',
    version: 1,
    listId: 'board',
    title: id,
    status: status,
    columnId: column,
    assignees: '',
    tags: '',
    position: position,
  );

  group('the column a card stands in', () {
    test('an open card in a column stands there', () {
      expect(columnOf(card('a', column: 'doing'), columns), equals('doing'));
    });

    test('a done card stands in the done column, whatever it says', () {
      expect(
        columnOf(card('a', status: 'DONE', column: 'todo'), columns),
        equals('done'),
      );
    });

    test(
      'an open card without a column, or with a deleted one, stands first',
      () {
        expect(columnOf(card('a'), columns), equals('todo'));
        expect(columnOf(card('a', column: 'gone'), columns), equals('todo'));
      },
    );

    test('with two done columns, a done card stays in its own', () {
      const archived = KanbanColumn(
        id: 'archived',
        name: 'Archived',
        done: true,
      );
      const board = [todo, doing, done, archived];
      expect(
        columnOf(card('a', status: 'DONE', column: 'archived'), board),
        equals('archived'),
      );
      // Ticked off elsewhere: the first done column.
      expect(
        columnOf(card('a', status: 'DONE', column: 'doing'), board),
        equals('done'),
      );
    });

    test('an open card that claims the done column stands first', () {
      // Unticked on one device while another had moved it there.
      expect(columnOf(card('a', column: 'done'), columns), equals('todo'));
    });

    test('cards are ordered by position within their column', () {
      final arranged = arrangeCards([
        card('b', column: 'doing', position: 2048),
        card('a', column: 'doing', position: 1024),
        card('c'),
      ], columns);

      expect(arranged['doing']!.map((t) => t.id), equals(['a', 'b']));
      expect(arranged['todo']!.map((t) => t.id), equals(['c']));
      expect(arranged['done'], isEmpty);
    });
  });

  group('positions', () {
    test('between two neighbours, before the first, after the last', () {
      expect(positionBetween(null, null), equals(0));
      expect(positionBetween(null, 0), equals(-positionStep));
      expect(positionBetween(0, null), equals(positionStep));
      expect(positionBetween(0, 1024), equals(512));
    });

    test('no room left means renumbering', () {
      expect(positionBetween(0, 0), isNull);
      expect(positionBetween(5, 6), isNull);
    });
  });

  group('the columns', () {
    test('2 to 8, a name each, at least one done and one open column', () {
      expect(columnsValid(columns), isTrue);
      expect(
        columnsValid([todo, done, done.copyWith(name: 'Archived')]),
        isFalse,
      );
      expect(
        columnsValid([
          todo,
          done,
          const KanbanColumn(id: 'archived', name: 'Archived', done: true),
        ]),
        isTrue,
      );
      expect(columnsValid([done]), isFalse);
      expect(columnsValid([todo, doing]), isFalse);
      expect(
        columnsValid([
          done,
          const KanbanColumn(id: 'archived', name: 'Archived', done: true),
        ]),
        isFalse,
      );
      expect(columnsValid([todo, done.copyWith(name: ' ')]), isFalse);
      expect(
        columnsValid([
          for (var i = 0; i < 9; i++)
            KanbanColumn(id: '$i', name: '$i', done: i == 0),
        ]),
        isFalse,
      );
    });

    test('they survive the way through JSON', () {
      final stored = parseColumns(
        '[{"id":"todo","name":"To do","colorToken":"RUST","done":false},'
        '{"id":"done","name":"Done","done":true},{"broken":1}]',
      );
      expect(stored.map((c) => c.id), equals(['todo', 'done']));
      expect(stored.first.colorToken, equals('RUST'));
      expect(stored.last.done, isTrue);
      expect(parseColumns('not json'), isEmpty);
    });
  });

  group('changing the columns', () {
    test('the cards of a removed column move to the one before it', () {
      final changes = planColumnChange(
        columns,
        [todo, done],
        [card('a', column: 'doing'), card('b', column: 'todo')],
      );

      expect(changes.single.todo.id, equals('a'));
      expect(changes.single.fields, equals({'columnId': 'todo'}));
    });

    test('without an open column before it, to the one after it', () {
      final changes = planColumnChange(
        columns,
        [doing, done],
        [card('a', column: 'todo')],
      );

      expect(changes.single.to, equals('doing'));
    });

    test('done cards stay done and are not touched', () {
      final changes = planColumnChange(
        columns,
        [todo, done],
        [card('a', status: 'DONE', column: 'doing')],
      );

      expect(changes, isEmpty);
    });

    test('open cards in a column that becomes the done column are done', () {
      final changes = planColumnChange(
        columns,
        [todo, doing.copyWith(done: true), done.copyWith(done: false)],
        [card('a', column: 'doing')],
      );

      expect(
        changes.single.fields,
        equals({'status': 'DONE', 'columnId': 'doing'}),
      );
    });

    test('a second done column leaves the first one\'s cards alone', () {
      final changes = planColumnChange(
        columns,
        [todo, doing.copyWith(done: true), done],
        [card('a', column: 'doing'), card('b', status: 'DONE', column: 'done')],
      );

      expect(changes.single.todo.id, equals('a'));
      expect(changes.single.fields['status'], equals('DONE'));
    });

    test('renaming and reordering touch no card', () {
      final changes = planColumnChange(
        columns,
        [doing.copyWith(name: 'Busy'), todo, done],
        [card('a', column: 'doing'), card('b')],
      );

      expect(changes, isEmpty);
    });
  });
}
