import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/common/wire.dart';
import '../../core/db/hiwiski_database.dart';
import '../../core/common/ids.dart';
import '../../core/sync/local_writes.dart';
import '../../domain/common/change.dart';
import '../../domain/todo/kanban.dart';
import '../../domain/todo/todo_items.dart';
import '../../domain/todo/todo_models.dart';

/// Lists and tasks — **always against the local database**.
///
/// Never directly against the API, not even where the sync layer does nothing more than
/// pass things through. Every input goes through immediately and syncs
/// later; there is no "Saving, please wait".
class TodoRepository {
  /// [currentMemberId] answers who creates something now — the owner of what is
  /// created. `''` while nobody is signed in.
  TodoRepository({
    required this._db,
    required this._writes,
    required this._currentMemberId,
    Duration Function()? undoWindow,
  }) : _undoWindow = undoWindow ?? _defaultUndoWindow;

  /// How long "Undo" shows on this device (Account → Customize) — a deletion waits
  /// that long, and a little more, before it goes out.
  final Duration Function() _undoWindow;

  static Duration _defaultUndoWindow() => const .new(seconds: 8);

  final HiwiskiDatabase _db;

  /// Every write: the row and its mutation together. The UI has its answer from the
  /// local database at once; the server finds out when it is reachable.
  final LocalWrites _writes;
  final String Function() _currentMemberId;

  String get _ownerId => _currentMemberId();

  // --- Reading -----------------------------------------------------------------

  /// The lists — without the archived ones unless [archived] asks for exactly those.
  ///
  /// Everything that offers lists reads the active ones: the overview, the start board,
  /// the target for a new task or a recipe's ingredients.
  /// The lists with their open and done counts — **one** watched query over lists and
  /// todos. It used to watch only the lists and read the todos once per emit: checking
  /// off an item left the overview's counts and progress bars stale until a list row
  /// changed, and every emit ran one query per list.
  Stream<List<TodoListSummary>> watchLists({bool archived = false}) {
    final todos = _db.todos;
    final lists = _db.todoLists;
    final count = todos.id.count();
    final query =
        _db.select(lists).join([
            leftOuterJoin(
              todos,
              todos.listId.equalsExp(lists.id) & todos.deletedAt.isNull(),
            ),
          ])
          ..where(lists.deletedAt.isNull())
          ..where(
            archived ? lists.archivedAt.isNotNull() : lists.archivedAt.isNull(),
          )
          ..addColumns([todos.status, count])
          ..groupBy([lists.id, todos.status])
          ..orderBy([
            OrderingTerm.asc(lists.position),
            OrderingTerm.asc(lists.name),
          ]);

    return query.watch().map((rows) {
      final byList = <String, ({TodoListRow list, int open, int done})>{};
      for (final row in rows) {
        final list = row.readTable(lists);
        final status = row.read(todos.status);
        final n = status == null ? 0 : row.read(count) ?? 0;
        final before = byList[list.id] ?? (list: list, open: 0, done: 0);
        byList[list.id] = status == TodoStatuses.done
            ? (list: list, open: before.open, done: before.done + n)
            : (list: list, open: before.open + n, done: before.done);
      }
      return [
        for (final entry in byList.values)
          TodoListSummary(
            list: entry.list.toDomain(),
            open: entry.open,
            done: entry.done,
          ),
      ];
    });
  }

  Stream<TodoList?> watchList(String listId) =>
      (_db.select(_db.todoLists)..where((row) => row.id.equals(listId)))
          .watchSingleOrNull()
          .map((row) => row?.toDomain());

  /// Done items sit at the bottom and are struck through — unless
  /// [doneLast] is off (Account → Customize), then they keep their place.
  Stream<List<Todo>> watchTodos(String listId, {bool doneLast = true}) =>
      (_db.select(_db.todos)
            ..where((row) => row.listId.equals(listId) & row.deletedAt.isNull())
            // Done items to the bottom. `desc` on the status, because
            // 'OPEN' sorts alphabetically after 'DONE' -- ascending, checked-off items would sit
            // at the top, and the list would reshuffle itself under your finger when checking off.
            ..orderBy([
              if (doneLast) (row) => OrderingTerm.desc(row.status),
              (row) => OrderingTerm.asc(row.position),
              (row) => OrderingTerm.asc(row.title),
            ]))
          .watch()
          .map((rows) => [for (final row in rows) row.toDomain()]);

  Stream<Todo?> watchTodo(String todoId) =>
      (_db.select(_db.todos)..where((row) => row.id.equals(todoId)))
          .watchSingleOrNull()
          .map((row) => row?.toDomain());

  /// Every task that is not deleted, across all lists — for the link index.
  Stream<List<Todo>> watchAllTodos() =>
      (_db.select(_db.todos)..where((row) => row.deletedAt.isNull()))
          .watch()
          .map((rows) => [for (final row in rows) row.toDomain()]);

  /// Every list that is not deleted, archived ones included — for the link index.
  Stream<List<TodoList>> watchAllLists() =>
      (_db.select(_db.todoLists)..where((row) => row.deletedAt.isNull()))
          .watch()
          .map((rows) => [for (final row in rows) row.toDomain()]);

  /// The ids of the archived lists — a task is archived with its list.
  Stream<Set<String>> watchArchivedListIds() =>
      (_db.select(_db.todoLists)..where((row) => row.archivedAt.isNotNull()))
          .watch()
          .map((rows) => {for (final row in rows) row.id});

  /// The list a task sits on — `null` if it is gone.
  Future<String?> listOf(String todoId) async {
    final row = await (_db.select(
      _db.todos,
    )..where((row) => row.id.equals(todoId))).getSingleOrNull();
    return row?.listId;
  }

  /// The checked-off and skipped occurrences of a series, newest first.
  Stream<List<TodoOccurrence>> watchOccurrences(String todoId) =>
      (_db.select(_db.todoOccurrences)
            ..where((row) => row.todoId.equals(todoId) & row.deletedAt.isNull())
            ..orderBy([(row) => OrderingTerm.desc(row.occurrenceDate)]))
          .watch()
          .map((rows) => [for (final row in rows) row.toDomain()]);

  // --- Writing -----------------------------------------------------------------

  Future<String> createList({
    required String name,
    required String kind,
    String? description,
    String colorToken = ColorTokens.blue,
    List<String> assignees = const [],
    List<String> tags = const [],
    List<KanbanColumn>? columns,
  }) async {
    final id = newId();
    final fields = <String, dynamic>{
      WireFields.name: name,
      WireFields.description: ?description,
      WireFields.kind: kind,
      if (columns != null) WireFields.columns: columnsToJson(columns),
      WireFields.colorToken: colorToken,
      if (assignees.isNotEmpty) WireFields.assignees: assignees,
      if (tags.isNotEmpty) WireFields.tags: tags,
    };

    await _writes.run(
      (write) => write.create(
        _db.todoLists,
        TodoListRow(
          id: id,
          ownerId: _ownerId,
          version: 0,
          name: name,
          description: description,
          kind: kind,
          columns: columns == null ? null : jsonEncode(columnsToJson(columns)),
          colorToken: colorToken,
          position: 0,
          assignees: assignees.join(','),
          tags: tags.join(','),
        ),
        fields: fields,
        label: name,
      ),
    );
    return id;
  }

  /// Creates a task.
  ///
  /// Attaches it to its list's still-pending mutation, if there is one: a task
  /// created offline in a list created offline must not go out
  /// if the list fails permanently.
  ///
  /// [done] and [dueTime] are for a task that arrives with a history — an import:
  /// it is created as it was, not created open and ticked off in a second change.
  Future<String> createTodo({
    required String listId,
    required String title,
    double? amount,
    String? unit,
    String? description,
    DateTime? dueDate,
    String? rrule,
    List<String> assignees = const [],
    List<String> tags = const [],
    String? columnId,
    int? position,
    bool done = false,
    String? dueTime,
  }) async {
    final id = newId();
    final status = done ? TodoStatuses.done : TodoStatuses.open;
    final fields = <String, dynamic>{
      WireFields.title: title,
      WireFields.status: status,
      WireFields.columnId: ?columnId,
      WireFields.amount: ?amount,
      WireFields.unit: ?unit,
      WireFields.description: ?description,
      if (dueDate != null) WireFields.dueDate: _dateOnly(dueDate),
      WireFields.dueTime: ?dueTime,
      WireFields.rrule: ?rrule,
      if (assignees.isNotEmpty) WireFields.assignees: assignees,
      if (tags.isNotEmpty) WireFields.tags: tags,
    };

    await _writes.run((write) async {
      // Without a position a new row goes to the end — of every kind of list, and on a
      // board of its column. Read here, inside the insert: two quick entries read the
      // same end outside it, got the same position and fell back to title order.
      final at = position ?? await _endFor(listId, columnId);
      if (at != 0) fields[WireFields.position] = at;
      await write.create(
        _db.todos,
        TodoRow(
          id: id,
          ownerId: _ownerId,
          version: 0,
          listId: listId,
          title: title,
          status: status,
          assignees: assignees.join(','),
          tags: tags.join(','),
          position: at,
          columnId: columnId,
          amount: amount,
          unit: unit,
          description: description,
          dueDate: dueDate,
          dueTime: dueTime,
          rrule: rrule,
        ),
        fields: fields,
        containerType: EntityTypes.todoList,
        containerId: listId,
        after: listId,
        label: title,
      );
    });
    return id;
  }

  /// Checks off or unchecks.
  ///
  /// Only that one field goes out. Whoever checks off while someone else moves the due
  /// date loses nothing.
  ///
  /// On a board the card moves with it: into the done column, or back to the first
  /// column.
  Future<void> setStatus(Todo todo, bool done) async {
    final status = done ? TodoStatuses.done : TodoStatuses.open;
    await _writes.run((write) async {
      final columns = await _boardColumns(todo.listId);
      final columnId = columns.isEmpty
          ? null
          : (done ? doneColumnOf(columns) : firstOpenColumnOf(columns)).id;
      await write.change(
        _db.todos,
        TodosCompanion(
          status: Value(status),
          columnId: columnId == null ? const Value.absent() : Value(columnId),
        ),
        id: todo.id,
        version: todo.version,
        fields: {WireFields.status: status, WireFields.columnId: ?columnId},
        containerType: EntityTypes.todoList,
        containerId: todo.listId,
        label: todo.title,
      );
    });
  }

  /// Unticks [todos] at once, in one run — "Untick all" on a task or shopping list.
  /// As with [setStatus], only the status goes out. Not for a board: there a card's
  /// column moves with it.
  Future<void> untickAll(List<Todo> todos) async {
    if (todos.isEmpty) return;
    await _writes.run((write) async {
      for (final todo in todos) {
        await write.change(
          _db.todos,
          const TodosCompanion(status: Value(TodoStatuses.open)),
          id: todo.id,
          version: todo.version,
          fields: {WireFields.status: TodoStatuses.open},
          containerType: EntityTypes.todoList,
          containerId: todo.listId,
          label: todo.title,
        );
      }
    });
  }

  /// The position after the last row of [listId] — on a board, after the last card
  /// of the column [columnId] (or the first open one) — with one aggregate query where
  /// that is enough.
  Future<int> _endFor(String listId, String? columnId) async {
    final columns = await _boardColumns(listId);
    final live = _db.todos.listId.equals(listId) & _db.todos.deletedAt.isNull();
    if (columns.isEmpty) {
      final last = _db.todos.position.max();
      final row =
          await (_db.selectOnly(_db.todos)
                ..addColumns([last])
                ..where(live))
              .getSingle();
      final top = row.read(last);
      return top == null ? 0 : top + positionStep;
    }
    final target = columnId ?? firstOpenColumnOf(columns).id;
    final rows = await (_db.select(_db.todos)..where((_) => live)).get();
    return endOfColumn([
      for (final row in rows)
        if (columnOf(row.toDomain(), columns) == target) row.toDomain(),
    ]);
  }

  /// The columns of a board — empty if the list is none.
  Future<List<KanbanColumn>> _boardColumns(String listId) async {
    final list = await (_db.select(
      _db.todoLists,
    )..where((row) => row.id.equals(listId))).getSingleOrNull();
    return list != null && list.kind == kindKanban
        ? parseColumns(list.columns)
        : const [];
  }

  /// Moves a card to [column], before the card at [index] of that column's cards —
  /// at the end without one.
  ///
  /// Writes `columnId`, and `status` when it crosses the done column. With [reorder]
  /// off — *check off* moves between columns but does not reorder —
  /// the card keeps its position.
  Future<void> moveCard(
    Todo card,
    KanbanColumn column, {
    required List<Todo> columnCards,
    int? index,
    bool reorder = true,
  }) async {
    final others = [
      for (final other in columnCards)
        if (other.id != card.id) other,
    ];
    final at = (index ?? others.length).clamp(0, others.length);
    final status = column.done ? TodoStatuses.done : TodoStatuses.open;
    final fields = <String, dynamic>{
      WireFields.columnId: column.id,
      if (status != card.status) WireFields.status: status,
    };

    await _writes.run((write) async {
      if (reorder) {
        fields[WireFields.position] = await _positionAt(write, others, at);
      }
      await _write(write, card, fields);
    });
  }

  /// Puts [item] at [at] among [others] — the rows it is sorted with, itself left
  /// out. A shopping row within its category.
  Future<void> reposition(
    Todo item, {
    required List<Todo> others,
    required int at,
  }) async {
    await _writes.run((write) async {
      final position = await _positionAt(
        write,
        others,
        at.clamp(0, others.length),
      );
      if (position != item.position) {
        await _write(write, item, {WireFields.position: position});
      }
    });
  }

  /// The position for a row at [at] among [others]; renumbers them first when there is
  /// no room between the two neighbours.
  Future<int> _positionAt(LocalWrite write, List<Todo> others, int at) async {
    final position = positionBetween(
      at == 0 ? null : others[at - 1].position,
      at == others.length ? null : others[at].position,
    );
    if (position != null) return position;
    await _renumber(write, others);
    return at * positionStep - positionStep ~/ 2;
  }

  /// Positions in steps, in the given order — so a card fits in between again.
  Future<void> _renumber(LocalWrite write, List<Todo> cards) async {
    for (final (index, card) in cards.indexed) {
      final position = index * positionStep;
      if (card.position == position) continue;
      await _write(write, card, {WireFields.position: position});
    }
  }

  /// Writes a card's board fields — or a row's position — locally and into the outbox.
  Future<void> _write(
    LocalWrite write,
    Todo card,
    Map<String, dynamic> fields,
  ) async {
    await write.change(
      _db.todos,
      TodosCompanion(
        columnId: fields.containsKey(WireFields.columnId)
            ? Value(fields[WireFields.columnId] as String?)
            : const Value.absent(),
        status: switch (fields[WireFields.status]) {
          final String status => Value(status),
          _ => const Value.absent(),
        },
        position: switch (fields[WireFields.position]) {
          final int position => Value(position),
          _ => const Value.absent(),
        },
        rrule: fields.containsKey(WireFields.rrule)
            ? Value(fields[WireFields.rrule] as String?)
            : const Value.absent(),
      ),
      id: card.id,
      version: card.version,
      fields: fields,
      containerType: EntityTypes.todoList,
      containerId: card.listId,
      label: card.title,
    );
  }

  /// Changes a board's columns — and the cards that a removed column or a new done
  /// column takes along ([planColumnChange]).
  Future<void> updateColumns(
    TodoList list,
    List<KanbanColumn> columns,
    List<Todo> cards,
  ) async {
    final changes = planColumnChange(
      parseColumns(list.columns),
      columns,
      cards,
    );
    await _writes.run((write) async {
      await _writeList(write, list, {
        WireFields.columns: columnsToJson(columns),
      });
      for (final change in changes) {
        await _write(write, change.todo, change.fields);
      }
    });
  }

  /// Turns a task list into a board. Repeats go first — a board has
  /// none, and the server would refuse them afterwards. The cards need no column of
  /// their own: open ones stand in the first column, done ones in the done column.
  Future<void> convertToKanban(
    TodoList list,
    List<KanbanColumn> columns,
    List<Todo> cards,
  ) async {
    await _writes.run((write) async {
      for (final card in cards) {
        if ((card.rrule ?? '').isNotEmpty) {
          await _write(write, card, {WireFields.rrule: null});
        }
      }
      await _writeList(write, list, {
        WireFields.kind: kindKanban,
        WireFields.columns: columnsToJson(columns),
      });
    });
  }

  /// The member's own order of the lists — ids, first first; empty while they have
  /// not sorted. Lists missing from it follow by their position.
  Stream<List<String>> watchListOrder() =>
      (_db.select(_db.listOrders)
            ..where((row) => row.id.equals(_ownerId) & row.deletedAt.isNull()))
          .watchSingleOrNull()
          .map(
            (row) => row == null
                ? const <String>[]
                : (jsonDecode(row.listIds) as List).cast<String>(),
          );

  /// Sets the member's own order of the lists — on every device of theirs, and on
  /// nobody else's. The row's id is the member's: every device writes the same one.
  Future<void> setListOrder(List<String> listIds) => _writes.run((write) async {
    final id = _ownerId;
    final fields = <String, dynamic>{WireFields.listIds: listIds};
    final encoded = Value(jsonEncode(listIds));
    final existing = await (_db.select(
      _db.listOrders,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (existing == null) {
      await write.create(
        _db.listOrders,
        ListOrdersCompanion.insert(id: id, ownerId: id, listIds: encoded),
        fields: fields,
        label: '',
      );
    } else {
      await write.change(
        _db.listOrders,
        ListOrdersCompanion(listIds: encoded, deletedAt: const Value(null)),
        id: id,
        version: existing.version,
        fields: fields,
        label: '',
      );
    }
  });

  Future<void> _writeList(
    LocalWrite write,
    TodoList list,
    Map<String, dynamic> fields,
  ) async {
    await write.change(
      _db.todoLists,
      TodoListsCompanion(
        kind: switch (fields[WireFields.kind]) {
          final String kind => Value(kind),
          _ => const Value.absent(),
        },
        columns: fields.containsKey(WireFields.columns)
            ? Value(jsonEncode(fields[WireFields.columns]))
            : const Value.absent(),
      ),
      id: list.id,
      version: list.version,
      fields: fields,
      label: list.name,
    );
  }

  /// Changes a task — each field only if given; [Change] clears what may be empty.
  Future<void> updateTodo(
    Todo todo, {
    String? title,
    Change<String?>? description,
    Change<DateTime?>? dueDate,
    Change<String?>? rrule,
    List<String>? assignees,
    List<String>? tags,
    Change<double?>? amount,
    Change<String?>? unit,
  }) {
    final fields = <String, dynamic>{
      WireFields.title: ?title,
      if (description != null) WireFields.description: description.value,
      if (dueDate != null)
        WireFields.dueDate: switch (dueDate.value) {
          final date? => _dateOnly(date),
          null => null,
        },
      if (rrule != null) WireFields.rrule: rrule.value,
      WireFields.assignees: ?assignees,
      WireFields.tags: ?tags,
      if (amount != null) WireFields.amount: amount.value,
      if (unit != null) WireFields.unit: unit.value,
    };
    return fields.isEmpty ? Future.value() : _updateTodo(todo, fields);
  }

  Future<void> _updateTodo(Todo todo, Map<String, dynamic> fields) async {
    await _writes.run(
      (write) => write.change(
        _db.todos,
        TodosCompanion(
          title: switch (fields[WireFields.title]) {
            final String title => Value(title),
            _ => const Value.absent(),
          },
          description: fields.containsKey(WireFields.description)
              ? Value(fields[WireFields.description] as String?)
              : const Value.absent(),
          dueDate: fields.containsKey(WireFields.dueDate)
              ? Value(switch (fields[WireFields.dueDate]) {
                  final String due => DateTime.parse(due),
                  _ => null,
                })
              : const Value.absent(),
          rrule: fields.containsKey(WireFields.rrule)
              ? Value(fields[WireFields.rrule] as String?)
              : const Value.absent(),
          assignees: _joined(fields, WireFields.assignees),
          tags: _joined(fields, WireFields.tags),
          amount: fields.containsKey(WireFields.amount)
              ? Value((fields[WireFields.amount] as num?)?.toDouble())
              : const Value.absent(),
          unit: fields.containsKey(WireFields.unit)
              ? Value(fields[WireFields.unit] as String?)
              : const Value.absent(),
        ),
        id: todo.id,
        version: todo.version,
        fields: fields,
        containerType: EntityTypes.todoList,
        containerId: todo.listId,
        label: todo.title,
      ),
    );
  }

  /// Tasks deleted a moment ago, still to be taken back: id → the timer that deletes
  /// them for good. The rows stay in the database until then; the lists leave them
  /// out ([watchPendingDeletes]).
  final _pendingDeletes = <String, Timer>{};
  final _pendingChanges = StreamController<Set<String>>.broadcast();

  /// How long a deleted task can be taken back — a little longer than the note that
  /// offers it stays.
  Duration get deleteGrace => _undoWindow() + _graceBeyondUndo;

  /// A little longer than "Undo" shows: tapped in its last moment, it still works.
  static const _graceBeyondUndo = Duration(milliseconds: 500);

  /// The tasks deleted but still to be taken back — what the lists leave out.
  Stream<Set<String>> watchPendingDeletes() async* {
    yield {..._pendingDeletes.keys};
    yield* _pendingChanges.stream;
  }

  void _pendingChanged() => _pendingChanges.add({..._pendingDeletes.keys});

  /// Deletes [todo] after [deleteGrace] unless [undoDelete] comes first. Waiting
  /// here and not on the server: taking it back works offline as well, and needs
  /// nothing restored. The timer lives with the repository, not the screen — leaving
  /// the list does not keep the task.
  void deleteTodoSoon(Todo todo) {
    _pendingDeletes[todo.id]?.cancel();
    _pendingDeletes[todo.id] = Timer(
      deleteGrace,
      () => unawaited(_deleteNow(todo.id)),
    );
    _pendingChanged();
  }

  /// The moment has passed: deletes the task as it is now — another device may have
  /// changed it meanwhile. Runs on a timer: a failure is logged, not thrown.
  Future<void> _deleteNow(String todoId) async {
    _pendingDeletes.remove(todoId);
    try {
      final current = await (_db.select(
        _db.todos,
      )..where((row) => row.id.equals(todoId))).getSingleOrNull();
      if (current != null && current.deletedAt == null) {
        await deleteTodo(current.toDomain());
      }
    } catch (error) {
      debugPrint('hiwiski: deleting a task failed: $error');
    } finally {
      _pendingChanged();
    }
  }

  /// Takes a deletion back while it can be.
  void undoDelete(String todoId) {
    _pendingDeletes.remove(todoId)?.cancel();
    _pendingChanged();
  }

  /// Soft delete, locally and as a mutation.
  ///
  /// The item goes to the trash; the tombstone carries it.
  Future<void> deleteTodo(Todo todo) async {
    await _writes.run(
      (write) => write.delete(
        _db.todos,
        id: todo.id,
        version: todo.version,
        label: todo.title,
      ),
    );
  }

  /// Changes a list: name, assignment, tags. The kind stays as it is.
  Future<void> updateList(
    TodoList list, {
    String? name,
    Change<String?>? description,
    List<String>? assignees,
    List<String>? tags,
  }) {
    final fields = <String, dynamic>{
      WireFields.name: ?name,
      if (description != null) WireFields.description: description.value,
      WireFields.assignees: ?assignees,
      WireFields.tags: ?tags,
    };
    return fields.isEmpty ? Future.value() : _updateList(list, fields);
  }

  Future<void> _updateList(TodoList list, Map<String, dynamic> fields) async {
    await _writes.run(
      (write) => write.change(
        _db.todoLists,
        TodoListsCompanion(
          name: switch (fields[WireFields.name]) {
            final String name => Value(name),
            _ => const Value.absent(),
          },
          description: fields.containsKey(WireFields.description)
              ? Value(fields[WireFields.description] as String?)
              : const Value.absent(),
          assignees: _joined(fields, WireFields.assignees),
          tags: _joined(fields, WireFields.tags),
        ),
        id: list.id,
        version: list.version,
        fields: fields,
        label: list.name,
      ),
    );
  }

  /// Archives the list — and its tasks with it, which carry no flag of their own.
  /// Nothing is deleted; [restoreList] undoes it.
  Future<void> archiveList(TodoList list) => _setArchived(list, archived: true);

  Future<void> restoreList(TodoList list) =>
      _setArchived(list, archived: false);

  Future<void> _setArchived(TodoList list, {required bool archived}) async {
    final at = archived ? clock.now() : null;
    final by = archived ? _ownerId : null;
    await _writes.run(
      (write) => write.change(
        _db.todoLists,
        TodoListsCompanion(archivedAt: Value(at), archivedBy: Value(by)),
        id: list.id,
        version: list.version,
        fields: {
          WireFields.archivedAt: at?.toUtc().toIso8601String(),
          WireFields.archivedBy: by,
        },
        label: list.name,
      ),
    );
  }

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  /// A collection of IDs, stored locally comma-separated.
  static Value<String> _joined(Map<String, dynamic> fields, String key) =>
      fields.containsKey(key)
      ? .new((fields[key] as List?)?.join(',') ?? '')
      : const .absent();

  Future<void> deleteList(TodoList list) async {
    await _writes.run(
      (write) => write.delete(
        _db.todoLists,
        id: list.id,
        version: list.version,
        label: list.name,
      ),
    );
  }
}

extension on TodoListRow {
  TodoList toDomain() => .new(
    id: id,
    ownerId: ownerId,
    version: version,
    deletedAt: deletedAt,
    name: name,
    entityKey: entityKey,
    description: description,
    kind: kind,
    columns: columns,
    colorToken: colorToken,
    position: position,
    assignees: assignees,
    tags: tags,
    archivedAt: archivedAt,
    archivedBy: archivedBy,
  );
}

extension on TodoRow {
  Todo toDomain() => .new(
    id: id,
    ownerId: ownerId,
    version: version,
    deletedAt: deletedAt,
    listId: listId,
    entityKey: entityKey,
    title: title,
    description: description,
    status: status,
    columnId: columnId,
    dueDate: dueDate,
    dueTime: dueTime,
    rrule: rrule,
    assignees: assignees,
    tags: tags,
    position: position,
    amount: amount,
    unit: unit,
    productId: productId,
  );
}

extension on TodoOccurrenceRow {
  TodoOccurrence toDomain() => .new(
    id: id,
    ownerId: ownerId,
    version: version,
    deletedAt: deletedAt,
    todoId: todoId,
    occurrenceDate: occurrenceDate,
    doneAt: doneAt,
    doneBy: doneBy,
    skipped: skipped,
  );
}
