import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/wiki/page_moves.dart';
import 'package:hiwiski/domain/wiki/wiki_models.dart';
import 'package:hiwiski/domain/wiki/wiki_page.dart';

/// **Pages move by drag and drop** — before, inside or after another row.
void main() {
  WikiPage page(String id, {String? parent, int position = 0}) => .new(
    id: id,
    ownerId: 'anna',
    version: 1,
    tags: '',
    parentId: parent,
    position: position,
    kind: 'PAGE',
    title: id,
    content: '',
  );

  final tree = WikiNode.build([
    page('A', position: 0),
    page('B', position: 1024),
    page('C', position: 2048),
    page('B1', parent: 'B'),
    page('B2', parent: 'B', position: 1024),
  ]);

  List<String> ids(DropPlan? plan) => [
    for (final page in plan?.siblings ?? const <WikiPage>[]) page.id,
  ];

  test('after a row: its parent, right behind it', () {
    final plan = dropPlan(tree, 'A', 'C', .after);
    expect(plan?.parentId, isNull);
    expect(ids(plan), equals(['B', 'C', 'A']));
  });

  test('before a subpage: into its parent, right in front of it', () {
    final plan = dropPlan(tree, 'C', 'B2', .before);
    expect(plan?.parentId, equals('B'));
    expect(ids(plan), equals(['B1', 'C', 'B2']));
  });

  test('inside a row: its last subpage', () {
    final plan = dropPlan(tree, 'A', 'B', .inside);
    expect(plan?.parentId, equals('B'));
    expect(ids(plan), equals(['B1', 'B2', 'A']));
  });

  test('not onto itself, not into its own subtree', () {
    expect(dropPlan(tree, 'B', 'B', .inside), isNull);
    expect(dropPlan(tree, 'B', 'B1', .inside), isNull);
    expect(dropPlan(tree, 'B', 'B2', .after), isNull);
  });

  group('positionsFor', () {
    test('room between the neighbours: only the moved page changes', () {
      final siblings = [
        page('A', position: 0),
        page('X', position: 5000),
        page('B', position: 1024),
      ];
      expect(positionsFor(siblings, 'X'), equals({'X': 512}));
    });

    test('no room — every page on 0, as they start — renumbers the row', () {
      final siblings = [page('A'), page('X'), page('B')];
      expect(positionsFor(siblings, 'X'), equals({'X': 1024, 'B': 2048}));
    });

    test('at the end, after the last', () {
      final siblings = [page('A', position: 0), page('X', position: 0)];
      expect(positionsFor(siblings, 'X'), equals({'X': 1024}));
    });
  });
}
