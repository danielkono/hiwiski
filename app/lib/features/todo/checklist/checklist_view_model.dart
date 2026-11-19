import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../app/stores.dart';
import '../../../core/api/generated/export.dart';
import '../../../domain/access/access_rules.dart';
import '../../../domain/common/change.dart';
import '../../../domain/common/item_ref.dart';
import '../../../domain/todo/kanban.dart';
import '../../../domain/todo/list_rules.dart' as rules;
import '../../../domain/todo/todo_items.dart';
import '../../../domain/todo/todo_models.dart';
import '../../../domain/wiki/markdown_editing.dart';

part 'checklist_view_model.g.dart';

/// A task list as its screen shows it.
@immutable
class ChecklistState {
  const ChecklistState({
    required this.list,
    required this.items,
    required this.level,
    required this.me,
    required this.members,
    required this.doneLast,
  });

  final TodoList list;

  /// In the list's order — done items at the bottom unless the device keeps them in
  /// place.
  final List<Todo> items;

  /// The reader's level on the list; `null` while unknown.
  final AccessLevel? level;

  /// Who is signed in — an assignment adds *check off* for a task.
  final String? me;

  /// The family by id, for the names in a row's meta line.
  final Map<String, Member> members;

  /// Whether done rows sit at the bottom, each status in its own order — or where
  /// they were, all rows in one (Account → Customize).
  final bool doneLast;

  String? get archivedBy => members[list.archivedBy]?.displayName;

  bool get writable => rules.listWritable(list, level);

  bool get mayChange => mayWrite(level);

  /// Deleting the list — its owner's, unlike archiving it.
  bool get mayDelete => rules.mayDeleteList(list, level, me);

  int get open => rules.openCount(items);

  /// The ticked-off entries — what "Untick all" and "Delete ticked-off" touch.
  List<Todo> get done => rules.doneItems(items);

  bool mayCheckOff(Todo todo) =>
      rules.mayCheckOff(list, todo, level: level, me: me);
}

@riverpod
Stream<TodoList?> _list(Ref ref, String listId) =>
    ref.watch(todoRepositoryProvider).watchList(listId);

/// Tasks deleted a moment ago that can still be taken back — left out of the list.
@riverpod
Stream<Set<String>> _pendingDeletes(Ref ref) =>
    ref.watch(todoRepositoryProvider).watchPendingDeletes();

/// The rows in the order the device wants them: done ones at the bottom, or where
/// they were (Account → Customize).
@riverpod
Stream<List<Todo>> _items(Ref ref, String listId) => ref
    .watch(todoRepositoryProvider)
    .watchTodos(
      listId,
      doneLast: ref.watch(preferencesProvider.select((p) => p.doneLast)),
    );

@riverpod
Stream<ShareSheet> _shares(Ref ref, String listId) => ref
    .watch(accessRepositoryProvider)
    .watchShareSheet(ItemRef.todoList(listId));

@riverpod
Stream<List<Member>> _members(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchMembers();

/// A task list: its rows, done ones at the bottom. `null` once the
/// list is gone.
@riverpod
class ChecklistViewModel extends _$ChecklistViewModel {
  @override
  Future<ChecklistState?> build(String listId) async {
    // From the server — not waited for: offline they may never come.
    final level = ref.watch(_sharesProvider(listId)).value?.myLevel;
    final members = ref.watch(_membersProvider).value ?? const <Member>[];
    final me = ref.watch(sessionProvider.select((s) => s.member?.id));
    final doneLast = ref.watch(preferencesProvider.select((p) => p.doneLast));
    final list = ref.watch(_listProvider(listId).future);
    final items = ref.watch(_itemsProvider(listId).future);
    final deleted = ref.watch(_pendingDeletesProvider).value ?? const {};
    final row = await list;
    if (row == null) return null;
    return ChecklistState(
      list: row,
      items: [
        for (final item in await items)
          if (!deleted.contains(item.id)) item,
      ],
      level: level,
      me: me,
      members: {for (final member in members) member.id: member},
      doneLast: doneLast,
    );
  }

  Future<void> setStatus(Todo todo, bool done) =>
      ref.read(todoRepositoryProvider).setStatus(todo, done);

  /// Ticks the [index]-th box of the list's description, as on a wiki page.
  Future<void> toggleDescriptionTask(TodoList list, int index) => rename(
    list,
    description: Change(toggleTask(list.description ?? '', index)),
  );

  Future<void> rename(
    TodoList list, {
    String? name,
    Change<String?>? description,
  }) => ref
      .read(todoRepositoryProvider)
      .updateList(list, name: name, description: description);

  Future<void> archive(TodoList list) =>
      ref.read(todoRepositoryProvider).archiveList(list);

  Future<void> restore(TodoList list) =>
      ref.read(todoRepositoryProvider).restoreList(list);

  Future<void> delete(TodoList list) =>
      ref.read(todoRepositoryProvider).deleteList(list);

  /// A task's title, edited in its row.
  Future<void> renameItem(Todo todo, String title) =>
      ref.read(todoRepositoryProvider).updateTodo(todo, title: title);

  /// A task dragged onto the row [onRow]: it goes [before] or after it — the list's
  /// own order, kept in the rows' positions.
  Future<void> moveItem(
    Todo todo, {
    required Todo onRow,
    required bool before,
  }) async {
    final current = state.value;
    if (current == null) return;
    final (:others, :at) = dropPlace(
      todo,
      rows: current.items,
      onRow: onRow,
      before: before,
      byStatus: current.doneLast,
    );
    await ref
        .read(todoRepositoryProvider)
        .reposition(todo, others: others, at: at);
  }

  /// A new task from the quick entry, with the tags picked there.
  Future<void> add(
    TodoList list, {
    required String title,
    List<String> tags = const [],
  }) => ref
      .read(todoRepositoryProvider)
      .createTodo(listId: list.id, title: title, tags: tags);

  /// Once and only in this direction: a task list may become a board.
  Future<void> convertToKanban(
    TodoList list,
    List<KanbanColumn> columns,
    List<Todo> cards,
  ) => ref.read(todoRepositoryProvider).convertToKanban(list, columns, cards);

  /// Deletes the task [todo] — after a moment in which [undoDeleteItem] takes it
  /// back.
  void deleteItem(Todo todo) =>
      ref.read(todoRepositoryProvider).deleteTodoSoon(todo);

  /// Takes a task's deletion back while it can be.
  void undoDeleteItem(String todoId) =>
      ref.read(todoRepositoryProvider).undoDelete(todoId);

  /// Unticks every entry in [done] at once.
  Future<void> untickAll(List<Todo> done) =>
      ref.read(todoRepositoryProvider).untickAll(done);

  /// Deletes the ticked-off entries [done] — after the same moment as a single row,
  /// in which [undoDeleteItems] takes them back.
  void deleteDone(List<Todo> done) {
    final todos = ref.read(todoRepositoryProvider);
    for (final todo in done) {
      todos.deleteTodoSoon(todo);
    }
  }

  /// Takes the deletion of [todoIds] back while it can be.
  void undoDeleteItems(Iterable<String> todoIds) {
    final todos = ref.read(todoRepositoryProvider);
    for (final id in todoIds) {
      todos.undoDelete(id);
    }
  }
}
