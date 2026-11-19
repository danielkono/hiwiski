import 'dart:convert';
import 'dart:math' show max;

import '../../core/common/ids.dart';
import '../../core/common/wire.dart';
import 'todo_items.dart';

/// The kind of a Kanban board.
const kindKanban = 'KANBAN';

/// Fewer is no board; more does not fit next to each other on a laptop. The server
/// checks the same numbers (`todo.kanban_columns_invalid`).
const kanbanMinColumns = 2;
const kanbanMaxColumns = 8;

/// The gap between two cards' positions — room to drop a card in between without
/// renumbering the column.
const positionStep = 1024;

/// The position for a new card at the bottom of a column.
int endOfColumn(List<Todo> columnCards) => columnCards.isEmpty
    ? 0
    : columnCards.map((card) => card.position).reduce(max) + positionStep;

/// A column of a board. A card names it by [id], so renaming or recoloring moves no
/// card (Kanban).
class KanbanColumn {
  // The fields of a column in the list's `columns`.
  static const _idField = 'id';
  static const _nameField = 'name';
  static const _colorTokenField = 'colorToken';
  static const _doneField = 'done';

  const KanbanColumn({
    required this.id,
    required this.name,
    this.colorToken = ColorTokens.blue,
    this.done = false,
  });

  /// A new column with a fresh id.
  factory KanbanColumn.create(
    String name, {
    String colorToken = ColorTokens.blue,
    bool done = false,
  }) => .new(id: newId(), name: name, colorToken: colorToken, done: done);

  final String id;
  final String name;
  final String colorToken;

  /// A done column — at least one per board, and at least one column stays open. A
  /// card in it is `DONE`.
  final bool done;

  // A column keeps its id: a copy is the same column, changed.
  // ignore: many_lints/avoid_incomplete_copy_with
  KanbanColumn copyWith({String? name, String? colorToken, bool? done}) => .new(
    id: id,
    name: name ?? this.name,
    colorToken: colorToken ?? this.colorToken,
    done: done ?? this.done,
  );

  Map<String, dynamic> toJson() => {
    _idField: id,
    _nameField: name,
    _colorTokenField: colorToken,
    _doneField: done,
  };

  static KanbanColumn? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value[_idField];
    if (id is! String || id.isEmpty) return null;
    return KanbanColumn(
      id: id,
      name: value[_nameField] as String? ?? '',
      colorToken: value[_colorTokenField] as String? ?? ColorTokens.blue,
      done: value[_doneField] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is KanbanColumn &&
      other.id == id &&
      other.name == name &&
      other.colorToken == colorToken &&
      other.done == done;

  @override
  int get hashCode => Object.hash(id, name, colorToken, done);
}

/// The columns as the list stores them. Tolerant: a broken value costs the board its
/// columns, not the app.
List<KanbanColumn> parseColumns(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [for (final element in decoded) ?KanbanColumn.fromJson(element)];
  } on FormatException {
    return const [];
  }
}

List<Map<String, dynamic>> columnsToJson(List<KanbanColumn> columns) => [
  for (final column in columns) column.toJson(),
];

/// What the server accepts: 2 to 8 columns, a name each, at least one done column
/// and at least one open one.
bool columnsValid(List<KanbanColumn> columns) =>
    columns.length >= kanbanMinColumns &&
    columns.length <= kanbanMaxColumns &&
    columns.every((column) => column.name.trim().isNotEmpty) &&
    columns.any((column) => column.done) &&
    columns.any((column) => !column.done) &&
    columns.map((column) => column.id).toSet().length == columns.length;

/// The first done column — where a card ticked off elsewhere goes — or the last one
/// if the data has none. Only for a board: the callers check for columns first.
KanbanColumn doneColumnOf(List<KanbanColumn> columns) =>
    columns.where((column) => column.done).firstOrNull ??
    switch (columns) {
      [..., final last] => last,
      [] => throw ArgumentError.value(columns, 'columns', 'no board'),
    };

/// Where a card goes that is open and has no column (any more). Only for a board: the
/// callers check for columns first.
KanbanColumn firstOpenColumnOf(List<KanbanColumn> columns) =>
    columns.where((column) => !column.done).firstOrNull ??
    switch (columns) {
      [final first, ...] => first,
      [] => throw ArgumentError.value(columns, 'columns', 'no board'),
    };

/// The column a card **stands in** — derived, never stored twice:
///
/// - done, in a done column that exists: that one;
/// - done otherwise: the first done column, whatever `columnId` says;
/// - open, in a column that exists and is not a done column: that one;
/// - open otherwise: the first column that is not a done column.
///
/// So status and column never contradict each other on screen, and a card whose column
/// was deleted on another device does not vanish.
String columnOf(Todo todo, List<KanbanColumn> columns) {
  final done = todo.status == TodoStatuses.done;
  final own = columns.where((column) => column.id == todo.columnId).firstOrNull;
  if (own != null && own.done == done) return own.id;
  return (done ? doneColumnOf(columns) : firstOpenColumnOf(columns)).id;
}

/// The cards by column, each column ordered by position, then title.
Map<String, List<Todo>> arrangeCards(
  List<Todo> todos,
  List<KanbanColumn> columns,
) {
  final byColumn = {for (final column in columns) column.id: <Todo>[]};
  if (columns.isEmpty) return byColumn;
  for (final todo in todos) {
    byColumn[columnOf(todo, columns)]!.add(todo);
  }
  for (final cards in byColumn.values) {
    cards.sort((a, b) {
      final byPosition = a.position.compareTo(b.position);
      return byPosition != 0 ? byPosition : a.title.compareTo(b.title);
    });
  }
  return byColumn;
}

/// A position between two neighbours, or `null` if there is no room — the column then
/// has to be renumbered first.
int? positionBetween(int? before, int? after) => switch ((before, after)) {
  (null, null) => 0,
  (null, final after?) => after - positionStep,
  (final before?, null) => before + positionStep,
  (final before?, final after?) when after - before < 2 => null,
  (final before?, final after?) => before + (after - before) ~/ 2,
};

/// A change to one card that a change of the columns brings along.
class const CardChange({
  required final Todo todo,

  /// What to write: `columnId`, and `status` where a column became the done column.
  required final Map<String, dynamic> fields,

  /// The column it stood in, and the one it stands in afterwards.
  required final String from,
  required final String to,
});

/// What happens to the cards when the columns change from [before] to [after]:
///
/// - the open cards of a removed column move to the nearest column before it that is
///   not a done column — after it, if there is none before;
/// - the open cards of a column that has become a done column are done now;
/// - done cards stay done; where their column is gone or open now, they stand in the
///   first done column.
List<CardChange> planColumnChange(
  List<KanbanColumn> before,
  List<KanbanColumn> after,
  List<Todo> todos,
) {
  if (before.isEmpty || after.isEmpty) return const [];
  final remaining = {for (final column in after) column.id: column};

  String neighbourOf(String columnId) {
    final index = before.indexWhere((column) => column.id == columnId);
    bool usable(KanbanColumn column) =>
        remaining[column.id] != null && !remaining[column.id]!.done;
    for (int i = index - 1; i >= 0; i--) {
      if (usable(before[i])) return before[i].id;
    }
    for (int i = index + 1; i < before.length; i++) {
      if (usable(before[i])) return before[i].id;
    }
    return firstOpenColumnOf(after).id;
  }

  final changes = <CardChange>[];
  for (final todo in todos) {
    if (todo.status == TodoStatuses.done) continue;
    final from = columnOf(todo, before);
    if (!remaining.containsKey(from)) {
      final to = neighbourOf(from);
      changes.add(
        CardChange(
          todo: todo,
          fields: {WireFields.columnId: to},
          from: from,
          to: to,
        ),
      );
    } else if (remaining[from]!.done) {
      changes.add(
        CardChange(
          todo: todo,
          fields: {
            WireFields.status: TodoStatuses.done,
            WireFields.columnId: from,
          },
          from: from,
          to: from,
        ),
      );
    }
  }
  return changes;
}
