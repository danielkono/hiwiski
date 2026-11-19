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
import '../../../domain/wiki/markdown_editing.dart';

part 'kanban_view_model.g.dart';

/// A board: the list's columns, its tasks as cards.
@immutable
class KanbanState {
  const KanbanState({
    required this.list,
    required this.items,
    required this.columns,
    required this.level,
    required this.me,
    required this.members,
  });

  final TodoList list;

  /// The cards, in the list's order.
  final List<Todo> items;

  final List<KanbanColumn> columns;

  /// The reader's level on the list; `null` while unknown.
  final AccessLevel? level;

  /// Who is signed in — an assignment lets a card move.
  final String? me;

  /// The family by id, for the names in a card's meta line.
  final Map<String, Member> members;

  String? get archivedBy => members[list.archivedBy]?.displayName;

  bool get writable => rules.listWritable(list, level);

  bool get mayChange => mayWrite(level);

  /// Deleting the list — its owner's, unlike archiving it.
  bool get mayDelete => rules.mayDeleteList(list, level, me);

  int get open => rules.openCount(items);

  /// Whether [card] may change its column.
  bool mayCheckOff(Todo card) =>
      rules.mayCheckOff(list, card, level: level, me: me);
}

@riverpod
Stream<TodoList?> _list(Ref ref, String listId) =>
    ref.watch(todoRepositoryProvider).watchList(listId);

/// Tasks deleted a moment ago that can still be taken back — left out of the list.
@riverpod
Stream<Set<String>> _pendingDeletes(Ref ref) =>
    ref.watch(todoRepositoryProvider).watchPendingDeletes();

@riverpod
Stream<List<Todo>> _items(Ref ref, String listId) =>
    ref.watch(todoRepositoryProvider).watchTodos(listId);

@riverpod
Stream<ShareSheet> _shares(Ref ref, String listId) => ref
    .watch(accessRepositoryProvider)
    .watchShareSheet(ItemRef.todoList(listId));

@riverpod
Stream<List<Member>> _members(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchMembers();

/// A board's page. `null` once the list is gone.
@riverpod
class KanbanViewModel extends _$KanbanViewModel {
  @override
  Future<KanbanState?> build(String listId) async {
    // From the server — not waited for: offline they may never come.
    final level = ref.watch(_sharesProvider(listId)).value?.myLevel;
    final members = ref.watch(_membersProvider).value ?? const <Member>[];
    final me = ref.watch(sessionProvider.select((s) => s.member?.id));
    final list = ref.watch(_listProvider(listId).future);
    final items = ref.watch(_itemsProvider(listId).future);
    final deleted = ref.watch(_pendingDeletesProvider).value ?? const {};
    final row = await list;
    if (row == null) return null;
    return KanbanState(
      list: row,
      items: [
        for (final item in await items)
          if (!deleted.contains(item.id)) item,
      ],
      columns: parseColumns(row.columns),
      level: level,
      me: me,
      members: {for (final member in members) member.id: member},
    );
  }

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

  /// A new card in [columnId], from the add field at the column's end.
  Future<void> add(
    TodoList list, {
    required String title,
    List<String> tags = const [],
    String? columnId,
  }) => ref
      .read(todoRepositoryProvider)
      .createTodo(
        listId: list.id,
        title: title,
        tags: tags,
        columnId: columnId,
      );

  /// A card into [column], before the card at [index] or at its end. [reorder]:
  /// whoever may only check off moves it between columns, not within one.
  /// A card's title, edited on the card.
  Future<void> renameItem(Todo todo, String title) =>
      ref.read(todoRepositoryProvider).updateTodo(todo, title: title);

  Future<void> moveCard(
    Todo card,
    KanbanColumn column, {
    required List<Todo> columnCards,
    int? index,
    bool reorder = true,
  }) => ref
      .read(todoRepositoryProvider)
      .moveCard(
        card,
        column,
        columnCards: columnCards,
        index: index,
        reorder: reorder,
      );

  Future<void> updateColumns(
    TodoList list,
    List<KanbanColumn> columns,
    List<Todo> cards,
  ) => ref.read(todoRepositoryProvider).updateColumns(list, columns, cards);

  /// Deletes the task [todo] — after a moment in which [undoDeleteItem] takes it
  /// back.
  void deleteItem(Todo todo) =>
      ref.read(todoRepositoryProvider).deleteTodoSoon(todo);

  /// Takes a task's deletion back while it can be.
  void undoDeleteItem(String todoId) =>
      ref.read(todoRepositoryProvider).undoDelete(todoId);
}
