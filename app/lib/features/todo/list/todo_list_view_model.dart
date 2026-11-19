import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../domain/todo/todo_items.dart';

part 'todo_list_view_model.g.dart';

@riverpod
Stream<TodoList?> _list(Ref ref, String listId) =>
    ref.watch(todoRepositoryProvider).watchList(listId);

/// Which kind of list sits behind an address — the checklist, shopping and Kanban
/// screens each show their own.
@riverpod
class TodoListViewModel extends _$TodoListViewModel {
  /// `null` once the list is gone.
  @override
  Future<String?> build(String listId) async =>
      (await ref.watch(_listProvider(listId).future))?.kind;
}
