import 'package:flutter/widgets.dart';

/// The keys the tests find this area's widgets by.
abstract final class WikiKeys {
  static const treeToggleAll = ValueKey('wiki-tree-toggle-all');
  static const newPage = ValueKey('new-page');
  static const newPageKind = ValueKey('new-page-kind');
  static const newPageTitle = ValueKey('new-page-title');
  static const newShoppingList = ValueKey('new-shopping-list');
  static const recipeContent = ValueKey('recipe-content');
  static const recipeDuration = ValueKey('recipe-duration');
  static const recipeIngredientList = ValueKey('recipe-ingredient-list');
  static const recipeServings = ValueKey('recipe-servings');
  static const recipeSource = ValueKey('recipe-source');
  static const recipeTitle = ValueKey('recipe-title');
  static const recipeUrl = ValueKey('recipe-url');
  static const wikiContent = ValueKey('wiki-content');
  static const wikiContentBelow = ValueKey('wiki-content-below');
  static const wikiTitle = ValueKey('wiki-title');

  static const _recipeIngredientHandle = 'recipe-ingredient-handle-';
  static ValueKey<String> recipeIngredientHandle(int index) =>
      .new('$_recipeIngredientHandle$index');
}
