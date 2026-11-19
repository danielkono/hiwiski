import 'package:meta/meta.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../core/api/generated/export.dart' hide Mutation;
import '../../../core/common/command.dart';
import '../../../core/common/wire.dart';
import '../../../domain/access/access_rules.dart';
import '../../../domain/catalog/catalog_product.dart';
import '../../../domain/common/change.dart';
import '../../../domain/wiki/markdown_editing.dart';
import '../../../domain/common/item_ref.dart';
import '../../../domain/todo/kanban.dart';
import '../../../domain/todo/todo_items.dart';

part 'todo_detail_view_model.g.dart';

/// `createAisle`, run by a view: it shows the command running and reacts to how it ended.
final createAisleForTodoMutation = Mutation<CatalogAisle>(
  label: 'todoDetailViewModel.createAisle',
);

/// A task as its page shows it.
@immutable
class TodoDetailState {
  const TodoDetailState({
    required this.todo,
    required this.list,
    this.level,
    this.members = const {},
    this.siblings = const [],
    this.products = const [],
    this.aisles = const [],
    this.occurrences = const [],
  });

  final Todo todo;
  final TodoList list;

  /// The reader's level on the task: *check off* toggles the box and nothing else;
  /// *read* not even that.
  final AccessLevel? level;
  final Map<String, Member> members;

  /// The other tasks of its list — a card's place in a column is among them.
  final List<Todo> siblings;

  final List<CatalogProduct> products;
  final List<CatalogAisle> aisles;

  /// A series' checked-off and skipped occurrences, newest first.
  final List<TodoOccurrence> occurrences;

  /// A task in an archived list is read-only with it.
  bool get archived => list.archivedAt != null;

  bool get writable => mayWrite(level) && !archived;

  bool get mayCheckOff => mayCheck(level) && !archived;

  /// A shopping item has a category instead of a due date and a repeat.
  bool get shopping => list.kind == ListKinds.shopping;

  /// On a board the column takes the place of the repeat.
  List<KanbanColumn> get columns => list.kind == kindKanban
      ? parseColumns(list.columns)
      : const <KanbanColumn>[];

  KanbanColumn? get column {
    if (columns.isEmpty) return null;
    return columns.firstWhere((c) => c.id == columnOf(todo, columns));
  }

  /// The category its product sits in.
  CatalogAisle? get aisle {
    if (!shopping) return null;
    final id = aisleFor(todo.title, todo.productId, products);
    return offeredAisles(aisles)
        .where((candidate) => candidate.id == id)
        .firstOrNull;
  }

  /// Who archived the list, by name.
  String? get archivedBy => members[list.archivedBy]?.displayName;
}

@riverpod
Stream<Todo?> _todo(Ref ref, String todoId) =>
    ref.watch(todoRepositoryProvider).watchTodo(todoId);

@riverpod
Stream<ShareSheet> _shares(Ref ref, String todoId) =>
    ref.watch(accessRepositoryProvider).watchShareSheet(ItemRef.todo(todoId));

@riverpod
Stream<List<TodoOccurrence>> _occurrences(Ref ref, String todoId) =>
    ref.watch(todoRepositoryProvider).watchOccurrences(todoId);

@riverpod
Stream<List<CatalogProduct>> _products(Ref ref) =>
    ref.watch(catalogRepositoryProvider).watch();

@riverpod
Stream<List<CatalogAisle>> _aisles(Ref ref) =>
    ref.watch(catalogRepositoryProvider).watchAisles();

@riverpod
Stream<TodoList?> _list(Ref ref, String listId) =>
    ref.watch(todoRepositoryProvider).watchList(listId);

@riverpod
Stream<List<Todo>> _siblings(Ref ref, String listId) =>
    ref.watch(todoRepositoryProvider).watchTodos(listId);

@riverpod
Stream<List<Member>> _members(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchMembers();

/// A task's page. `null` once the task or its list is gone.
@riverpod
class TodoDetailViewModel extends _$TodoDetailViewModel {
  @override
  Future<TodoDetailState?> build(String todoId) async {
    // From the server — not waited for: offline they may never come.
    final level = ref.watch(_sharesProvider(todoId)).value?.myLevel;
    final members = ref.watch(_membersProvider).value ?? const <Member>[];
    final todo = await ref.watch(_todoProvider(todoId).future);
    if (todo == null) return null;
    final list = ref.watch(_listProvider(todo.listId).future);
    final siblings = ref.watch(_siblingsProvider(todo.listId).future);
    final occurrences = (todo.rrule ?? '').isEmpty
        ? null
        : ref.watch(_occurrencesProvider(todoId).future);
    final row = await list;
    if (row == null) return null;
    final shopping = row.kind == ListKinds.shopping;
    final products = shopping ? ref.watch(_productsProvider.future) : null;
    final aisles = shopping ? ref.watch(_aislesProvider.future) : null;
    return TodoDetailState(
      todo: todo,
      list: row,
      level: level,
      members: {for (final member in members) member.id: member},
      siblings: await siblings,
      products: await products ?? const [],
      aisles: await aisles ?? const [],
      occurrences: await occurrences ?? const [],
    );
  }

  Future<void> setStatus(Todo todo, bool done) =>
      ref.read(todoRepositoryProvider).setStatus(todo, done);

  /// Ticks the [index]-th box of [todo]'s description, as on a wiki page.
  Future<void> toggleDescriptionTask(Todo todo, int index) => edit(
    todo,
    description: Change(toggleTask(todo.description ?? '', index)),
  );

  Future<void> edit(
    Todo todo, {
    String? title,
    Change<String?>? description,
    Change<DateTime?>? dueDate,
    Change<String?>? rrule,
  }) => ref
      .read(todoRepositoryProvider)
      .updateTodo(
        todo,
        title: title,
        description: description,
        dueDate: dueDate,
        rrule: rrule,
      );

  Future<void> delete(Todo todo) =>
      ref.read(todoRepositoryProvider).deleteTodo(todo);

  /// Into the column, at its end — the card's place among the others is the board's
  /// business. Whoever may only check off moves it between columns, not within one.
  Future<void> moveTo(KanbanColumn column) async {
    final current = state.value;
    if (current == null) return;
    final cards = arrangeCards(current.siblings, current.columns)[column.id]!;
    await ref
        .read(todoRepositoryProvider)
        .moveCard(
          current.todo,
          column,
          columnCards: cards,
          reorder: current.writable,
        );
  }

  /// The product with exactly this name goes into this category — in every list
  /// from now on; `null` is "Other". Needs a connection.
  Future<void> assignAisle(String productName, String? aisleId) => ref
      .read(catalogRepositoryProvider)
      .assignAisle(productName.trim(), aisleId);

  @command
  Future<CatalogAisle> createAisle(String name) =>
      ref.read(catalogRepositoryProvider).createAisle(name.trim());
}
