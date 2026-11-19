import 'package:hiwiski/domain/wiki/wiki_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/wiki/wiki_page.dart';

/// The page tree — **nested arbitrarily deep**.
///
/// The focus is on what can go wrong when two devices move pages offline: a cycle and a
/// page whose parent is missing. Neither may cost the display.
void main() {
  WikiPage page(
    String id, {
    String? parent,
    int position = 0,
    String kind = 'PAGE',
    bool archived = false,
  }) => .new(
    archivedAt: archived ? DateTime(2026, 3, 12) : null,
    id: id,
    ownerId: 'anna',
    version: 1,
    tags: '',
    parentId: parent,
    position: position,
    kind: kind,
    title: id,
    content: '',
  );

  test('three levels deep', () {
    final tree = WikiNode.build([
      page('House'),
      page('Tech', parent: 'House'),
      page('Router', parent: 'Tech'),
    ]);

    expect(tree, hasLength(1));
    expect(tree.single.page.id, equals('House'));
    expect(tree.single.children.single.page.id, equals('Tech'));
    expect(
      tree.single.children.single.children.single.page.id,
      equals('Router'),
    );
  });

  test('siblings are ordered by position, then by title', () {
    final tree = WikiNode.build([
      page('B', position: 2),
      page('A', position: 1),
      page('C', position: 1),
    ]);

    expect(tree.map((node) => node.page.id), equals(['A', 'C', 'B']));
  });

  test('a cycle does not send the tree into an endless loop', () {
    // Two devices moving pages in opposite directions offline can build one.
    final tree = WikiNode.build([
      page('A', parent: 'B'),
      page('B', parent: 'A'),
    ]);

    // Both used to vanish: no way led up to the root. Now the cycle is broken once,
    // and both pages are in the tree.
    expect(tree.single.page.id, equals('A'));
    expect(tree.single.children.single.page.id, equals('B'));
    expect(tree.single.children.single.children, isEmpty);
  });

  test('a page without a parent sits at the root instead of disappearing', () {
    // The parent may be gone because it was deleted or because the share is missing.
    // Visible and findable is better than gone.
    final tree = WikiNode.build([page('Orphan', parent: 'does-not-exist')]);

    expect(tree, hasLength(1));
    expect(tree.single.page.id, equals('Orphan'));
  });

  test('a recipe branch is recognized as such', () {
    // This decides whether the "+" menu offers "Subpage" or "Folder/Recipe".
    final tree = WikiNode.build([
      page('Recipes'),
      page('Soups', parent: 'Recipes'),
      page('Pumpkin soup', parent: 'Soups', kind: 'RECIPE'),
      page('House'),
    ]);

    final recipeBranch = tree.firstWhere((node) => node.page.id == 'Recipes');
    final house = tree.firstWhere((node) => node.page.id == 'House');

    expect(recipeBranch.isRecipeBranch, isTrue);
    expect(house.isRecipeBranch, isFalse);
  });

  test('an empty recipe collection is a recipe branch from the start', () {
    // Before, a branch only became one through a recipe in it — and the only way to a
    // first recipe was the import.
    final tree = WikiNode.build([
      page('Recipes', kind: kindRecipeFolder),
      page('House'),
    ]);

    final byId = {for (final node in tree) node.page.id: node};
    expect(byId['Recipes']!.isRecipeBranch, isTrue);
    expect(byId['House']!.isRecipeBranch, isFalse);
  });

  group('the archive', () {
    test('an archived page is not in the tree', () {
      final tree = WikiNode.buildActive([
        page('House'),
        page('Old flat', archived: true),
      ]);

      expect(tree.map((node) => node.page.id), equals(['House']));
    });

    test(
      '"only this page" leaves the subpages under the nearest active ancestor',
      () {
        final tree = WikiNode.buildActive([
          page('House'),
          page('Old flat', parent: 'House', archived: true),
          page('Utilities', parent: 'Old flat'),
        ]);

        // Shown under House, but its own parent stays — restoring puts it back.
        final utilities = tree.single.children.single;
        expect(utilities.page.id, equals('Utilities'));
        expect(utilities.page.parentId, equals('House'));
      },
    );

    test('a branch archived as a whole disappears entirely', () {
      final tree = WikiNode.buildActive([
        page('House'),
        page('Old flat', parent: 'House', archived: true),
        page('Utilities', parent: 'Old flat', archived: true),
      ]);

      expect(tree.single.children, isEmpty);
    });

    test('below an archived root a subpage moves up to the root', () {
      final tree = WikiNode.buildActive([
        page('Old flat', archived: true),
        page('Utilities', parent: 'Old flat'),
      ]);

      expect(tree.single.page.id, equals('Utilities'));
    });
  });

  // P has an archived child A, and A an active child G: G is part of P's branch, and
  // moving P under G built the cycle P → G → A → P.
  test('a branch reaches through an archived page', () {
    final branch = branchOf([
      page('P'),
      page('A', parent: 'P', archived: true),
      page('G', parent: 'A'),
      page('Other'),
    ], 'P');

    expect(branch, equals({'P', 'A', 'G'}));
  });

  test('the recipes under a page, even in a parent cycle', () {
    final pages = [
      page('Kitchen', parent: 'Soup'),
      page('Soup', parent: 'Kitchen', kind: 'RECIPE'),
      page('Bread', parent: 'Kitchen', kind: 'RECIPE', position: 1),
    ];

    expect(
      recipesUnder(pages, pages.first).map((p) => p.id),
      equals(['Soup', 'Bread']),
    );
  });

  test('a row counts subpages, a recipe branch its recipes at any depth', () {
    final tree = WikiNode.build([
      page('House'),
      page('Tech', parent: 'House'),
      page('Garden', parent: 'House'),
      page('Router', parent: 'Tech'),
      page('Recipes', kind: kindRecipeFolder),
      page('Soup', parent: 'Recipes', kind: 'RECIPE'),
      page('Baking', parent: 'Recipes', kind: kindRecipeFolder),
      page('Bread', parent: 'Baking', kind: 'RECIPE'),
      page('Cake', parent: 'Baking', kind: 'RECIPE'),
    ]);
    final house = tree.firstWhere((node) => node.page.id == 'House');
    final recipes = tree.firstWhere((node) => node.page.id == 'Recipes');

    expect(house.subpageCount, equals(2));
    expect(recipes.recipeCount, equals(3));
  });
}
