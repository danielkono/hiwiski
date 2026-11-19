import 'package:flutter/widgets.dart';

/// The keys the tests find this area's widgets by.
abstract final class TodoKeys {
  static const kanbanAddColumn = ValueKey('kanban-add-column');
  static const kanbanColumns = ValueKey('kanban-columns');
  static const kanbanColumnsSave = ValueKey('kanban-columns-save');
  static const kanbanConvert = ValueKey('kanban-convert');
  static const kanbanPages = ValueKey('kanban-pages');
  static const kindKanban = ValueKey('kind-kanban');
  static const listDeleteDone = ValueKey('list-delete-done');
  static const listDescription = ValueKey('list-description');
  static const listName = ValueKey('list-name');
  static const listUntickAll = ValueKey('list-untick-all');
  static const newTodoCreate = ValueKey('new-todo-create');
  static const todoColumn = ValueKey('todo-column');
  static const todoDescription = ValueKey('todo-description');
  static const todoTitleField = ValueKey('todo-title-field');

  static const _kanbanAdd = 'kanban-add-';
  static ValueKey<String> kanbanAdd(String id) => .new('$_kanbanAdd$id');

  static const _titleField = 'title-field-';
  static ValueKey<String> titleField(String id) => .new('$_titleField$id');

  static const _kanbanCard = 'kanban-card-';
  static ValueKey<String> kanbanCard(String id) => .new('$_kanbanCard$id');

  static const _kanbanColumn = 'kanban-column-';
  static ValueKey<String> kanbanColumn(String id) => .new('$_kanbanColumn$id');

  static const _kanbanColumnDone = 'kanban-column-done-';
  static ValueKey<String> kanbanColumnDone(String id) =>
      .new('$_kanbanColumnDone$id');

  static const _kanbanColumnName = 'kanban-column-name-';
  static ValueKey<String> kanbanColumnName(String id) =>
      .new('$_kanbanColumnName$id');

  static const _kanbanNew = 'kanban-new-';
  static ValueKey<String> kanbanNew(String id) => .new('$_kanbanNew$id');

  static const _kanbanTab = 'kanban-tab-';
  static ValueKey<String> kanbanTab(String id) => .new('$_kanbanTab$id');

  static const aisles = ValueKey('aisles');
  static const aisleAdd = ValueKey('aisle-add');
  static const aisleName = ValueKey('aisle-name');
  static const aisleNameSave = ValueKey('aisle-name-save');
  static const aisleDeleteConfirm = ValueKey('aisle-delete-confirm');
  static const todoAisle = ValueKey('todo-aisle');

  static const _aisleRow = 'aisle-row-';
  static ValueKey<String> aisleRow(String id) => .new('$_aisleRow$id');

  static const _aisleHide = 'aisle-hide-';
  static ValueKey<String> aisleHide(String id) => .new('$_aisleHide$id');

  static const _aisleDelete = 'aisle-delete-';
  static ValueKey<String> aisleDelete(String id) => .new('$_aisleDelete$id');

  static const _aisleOption = 'aisle-option-';
  static ValueKey<String> aisleOption(String id) => .new('$_aisleOption$id');

  static const shoppingOtherAisles = ValueKey('shopping-other-aisles');
  static const _shoppingRow = 'shopping-row-';
  static ValueKey<String> shoppingRow(String id) => .new('$_shoppingRow$id');
  static const _shoppingAisle = 'shopping-aisle-';
  static ValueKey<String> shoppingAisle(String id) =>
      .new('$_shoppingAisle$id');

  static const overviewViewMenu = ValueKey('overview-view-menu');

  static const _deleteTodo = 'delete-todo-';
  static ValueKey<String> deleteTodo(String id) => .new('$_deleteTodo$id');
  static const overviewRowsHide = ValueKey('overview-rows-hide');
  static const overviewRowsShow = ValueKey('overview-rows-show');

  static const _overviewView = 'overview-view-';
  static ValueKey<String> overviewView(String mode) =>
      .new('$_overviewView$mode');

  static const _overviewRow = 'overview-row-';
  static ValueKey<String> overviewRow(String listId) =>
      .new('$_overviewRow$listId');

  static const _categoryCard = 'category-card-';
  static ValueKey<String> categoryCard(String id) => .new('$_categoryCard$id');

  static const _categoryProduct = 'category-product-';
  static ValueKey<String> categoryProduct(String id) =>
      .new('$_categoryProduct$id');

  static const _categoryAddProduct = 'category-add-product-';
  static ValueKey<String> categoryAddProduct(String id) =>
      .new('$_categoryAddProduct$id');

  static const categoryNew = ValueKey('category-new');
  static const categorySearch = ValueKey('category-search');
}
