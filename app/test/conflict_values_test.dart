import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/domain/sync/conflict_values.dart';
import 'package:hiwiski/domain/todo/kanban.dart';

/// **A Kanban conflict is shown in names, not ids.** The sheet used to show a board's
/// columns as JSON and a card's column as a bare UUID.
void main() {
  const todo = KanbanColumn(id: 'c1', name: 'To do', colorToken: 'blue');
  const doing = KanbanColumn(id: 'c2', name: 'Doing', colorToken: 'amber');
  const done = KanbanColumn(
    id: 'c3',
    name: 'Done',
    colorToken: 'green',
    done: true,
  );
  final board = [todo, doing, done];

  test("a board's columns come as the columns, in order", () {
    final value = readConflictValue(
      WireFields.columns,
      jsonEncode(columnsToJson(board)),
    );
    expect(value, isA<ColumnsValue>());
    expect([
      for (final c in (value as ColumnsValue).columns) c.name,
    ], equals(['To do', 'Doing', 'Done']));
  });

  test("a card's column comes by name", () {
    final value = readConflictValue(
      WireFields.columnId,
      jsonEncode('c2'),
      board: board,
    );
    expect((value as ColumnValue).name, equals('Doing'));
  });

  test('a column that is gone says so, not its id', () {
    final value = readConflictValue(
      WireFields.columnId,
      jsonEncode('c9'),
      board: board,
    );
    expect((value as ColumnValue).name, isNull);
  });

  test('a status is ticked or not', () {
    expect(
      (readConflictValue(
        WireFields.status,
        jsonEncode('DONE'),
      ) as StatusValue).done,
      isTrue,
    );
    expect(
      (readConflictValue(
        WireFields.status,
        jsonEncode('OPEN'),
      ) as StatusValue).done,
      isFalse,
    );
  });

  test('anything else stays text, a list joined', () {
    final value = readConflictValue(WireFields.title, jsonEncode('Milk'));
    expect((value as TextValue).text, equals('Milk'));
    final list = readConflictValue(WireFields.tags, jsonEncode(['a', 'b']));
    expect((list as TextValue).text, equals('a, b'));
  });
}
