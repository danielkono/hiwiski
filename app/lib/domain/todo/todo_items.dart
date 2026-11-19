// The domain models of this feature, field for field what the local database
// stores. The repository maps its rows onto them: the layers above see these
// classes, never a Drift row.

/// A list: tasks, a shopping list or a Kanban board.
class TodoList {
  const TodoList({
    required this.id,
    required this.ownerId,
    required this.version,
    this.deletedAt,
    required this.name,
    this.entityKey,
    this.description,
    required this.kind,
    this.columns,
    required this.colorToken,
    required this.position,
    required this.assignees,
    required this.tags,
    this.archivedAt,
    this.archivedBy,
  });

  final String id;
  final String ownerId;
  final int version;
  final DateTime? deletedAt;
  final String name;

  /// The readable key (`LST-3`); `null` until the first sync.
  final String? entityKey;
  final String? description;
  final String kind;
  final String? columns;
  final String colorToken;
  final int position;
  final String assignees;
  final String tags;
  final DateTime? archivedAt;
  final String? archivedBy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TodoList &&
          other.id == id &&
          other.ownerId == ownerId &&
          other.version == version &&
          other.deletedAt == deletedAt &&
          other.name == name &&
          other.description == description &&
          other.kind == kind &&
          other.columns == columns &&
          other.colorToken == colorToken &&
          other.position == position &&
          other.assignees == assignees &&
          other.tags == tags &&
          other.archivedAt == archivedAt &&
          other.archivedBy == archivedBy;

  @override
  int get hashCode => Object.hashAll([
    id,
    ownerId,
    version,
    deletedAt,
    name,
    description,
    kind,
    columns,
    colorToken,
    position,
    assignees,
    tags,
    archivedAt,
    archivedBy,
  ]);
}

/// A task — on a list, a shopping list or a board.
class Todo {
  const Todo({
    required this.id,
    required this.ownerId,
    required this.version,
    this.deletedAt,
    required this.listId,
    this.entityKey,
    required this.title,
    this.description,
    required this.status,
    this.columnId,
    this.dueDate,
    this.dueTime,
    this.rrule,
    required this.assignees,
    required this.tags,
    required this.position,
    this.amount,
    this.unit,
    this.productId,
  });

  final String id;
  final String ownerId;
  final int version;
  final DateTime? deletedAt;
  final String listId;
  final String? entityKey;
  final String title;
  final String? description;
  final String status;
  final String? columnId;
  final DateTime? dueDate;
  final String? dueTime;
  final String? rrule;
  final String assignees;
  final String tags;
  final int position;
  final double? amount;
  final String? unit;
  final String? productId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Todo &&
          other.id == id &&
          other.ownerId == ownerId &&
          other.version == version &&
          other.deletedAt == deletedAt &&
          other.listId == listId &&
          other.entityKey == entityKey &&
          other.title == title &&
          other.description == description &&
          other.status == status &&
          other.columnId == columnId &&
          other.dueDate == dueDate &&
          other.dueTime == dueTime &&
          other.rrule == rrule &&
          other.assignees == assignees &&
          other.tags == tags &&
          other.position == position &&
          other.amount == amount &&
          other.unit == unit &&
          other.productId == productId;

  @override
  int get hashCode => Object.hashAll([
    id,
    ownerId,
    version,
    deletedAt,
    listId,
    entityKey,
    title,
    description,
    status,
    columnId,
    dueDate,
    dueTime,
    rrule,
    assignees,
    tags,
    position,
    amount,
    unit,
    productId,
  ]);
}

/// One occurrence of a recurring task: done, skipped or open.
class TodoOccurrence {
  const TodoOccurrence({
    required this.id,
    required this.ownerId,
    required this.version,
    this.deletedAt,
    required this.todoId,
    required this.occurrenceDate,
    this.doneAt,
    this.doneBy,
    required this.skipped,
  });

  final String id;
  final String ownerId;
  final int version;
  final DateTime? deletedAt;
  final String todoId;
  final DateTime occurrenceDate;
  final DateTime? doneAt;
  final String? doneBy;
  final bool skipped;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TodoOccurrence &&
          other.id == id &&
          other.ownerId == ownerId &&
          other.version == version &&
          other.deletedAt == deletedAt &&
          other.todoId == todoId &&
          other.occurrenceDate == occurrenceDate &&
          other.doneAt == doneAt &&
          other.doneBy == doneBy &&
          other.skipped == skipped;

  @override
  int get hashCode => Object.hashAll([
    id,
    ownerId,
    version,
    deletedAt,
    todoId,
    occurrenceDate,
    doneAt,
    doneBy,
    skipped,
  ]);
}
