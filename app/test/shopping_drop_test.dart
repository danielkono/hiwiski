import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/domain/todo/todo_items.dart';
import 'package:hiwiski/domain/todo/todo_models.dart';

/// **A shopping row is placed among the rows of its own status.** Open and done rows
/// are each ordered on their own; placed among both, a drop landed elsewhere and could
/// renumber the whole category.
void main() {
  Todo row(String id, String status, int position) => .new(
    id: id,
    ownerId: 'anna',
    version: 1,
    listId: 'l1',
    title: id,
    status: status,
    assignees: '',
    tags: '',
    position: position,
  );

  final a = row('A', TodoStatuses.open, 2048);
  final b = row('B', TodoStatuses.open, 3072);
  final c = row('C', TodoStatuses.done, 0);
  final x = row('X', TodoStatuses.open, 9000);

  test('an open row after a done one goes to the end of the open ones', () {
    final place = dropPlace(x, rows: [a, b, c, x], onRow: c, before: false);
    expect(place.others, equals([a, b]));
    expect(place.at, equals(2));
  });

  test('between open rows it goes where it was dropped', () {
    final place = dropPlace(x, rows: [a, b, c, x], onRow: b);
    expect(place.others, equals([a, b]));
    expect(place.at, equals(1));
  });

  test('a done row on an open one goes to the start of the done ones', () {
    final d = row('D', TodoStatuses.done, 500);
    final place = dropPlace(d, rows: [a, b, c, d], onRow: a);
    expect(place.others, equals([c]));
    expect(place.at, equals(0));
  });

  test(
    'without done rows at the bottom it goes right where it was dropped',
    () {
      final place = dropPlace(
        x,
        rows: [a, c, b, x],
        onRow: c,
        before: false,
        byStatus: false,
      );
      expect(place.others, equals([a, c, b]));
      expect(place.at, equals(2));
    },
  );
}
