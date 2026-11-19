import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../core/common/command.dart';
import '../../../core/common/wire.dart';
import '../../../domain/todo/todo_models.dart';
import '../../../domain/wiki/wiki_models.dart';

part 'recipe_shopping_view_model.g.dart';

/// `add`, run by a view: it shows the command running and reacts to how it ended.
final addToShoppingMutation = Mutation<String?>(
  label: 'recipeShoppingViewModel.add',
);

@riverpod
Stream<List<TodoListSummary>> _lists(Ref ref) =>
    ref.watch(todoRepositoryProvider).watchLists();

/// "Add to shopping list": the shopping lists to pick from, and the
/// ingredients going onto one.
@riverpod
class RecipeShoppingViewModel extends _$RecipeShoppingViewModel {
  /// The shopping lists — not task lists or boards.
  @override
  Future<List<TodoListSummary>> build() async => [
    for (final summary in await ref.watch(_listsProvider.future))
      if (summary.list.kind == ListKinds.shopping) summary,
  ];

  /// Puts [ingredients] onto the list [listId], or onto a new one called [newName].
  /// Returns the list's id — `null` when there is neither.
  @command
  Future<String?> add(
    List<Ingredient> ingredients, {
    String? listId,
    String newName = '',
  }) async {
    final todos = ref.read(todoRepositoryProvider);
    String? target = listId;
    if (target == null) {
      final name = newName.trim();
      if (name.isEmpty) return null;
      target = await todos.createList(name: name, kind: ListKinds.shopping);
    }
    for (final item in ingredients) {
      await todos.createTodo(
        listId: target,
        title: item.label,
        amount: item.amount,
        unit: item.unit,
      );
    }
    return target;
  }
}
