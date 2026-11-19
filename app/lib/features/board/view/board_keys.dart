import 'package:flutter/widgets.dart';

/// The keys the tests find this area's widgets by.
abstract final class BoardKeys {
  static const widgetKanbanBoard = ValueKey('widget-kanban-board');
  static const widgetKanbanColumn = ValueKey('widget-kanban-column');
  static const widgetKanbanOneColumn = ValueKey('widget-kanban-one-column');
  static const widgetNoteText = ValueKey('widget-note-text');

  static const _widgetKanbanCard = 'widget-kanban-card-';
  static ValueKey<String> widgetKanbanCard(String id) =>
      .new('$_widgetKanbanCard$id');

  static const _widgetTodo = 'widget-todo-';
  static ValueKey<String> widgetTodo(String id) => .new('$_widgetTodo$id');
}
