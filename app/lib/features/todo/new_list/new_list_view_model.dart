import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../core/api/generated/export.dart' hide Mutation;
import '../../../core/common/command.dart';
import '../../../core/common/wire.dart';
import '../../../domain/todo/kanban.dart';

part 'new_list_view_model.g.dart';

/// `create`, run by a view: it shows the command running and reacts to how it ended.
final createListMutation = Mutation<String>(label: 'newListViewModel.create');

/// "New list": creates it, with the shares chosen for it.
@riverpod
class NewListViewModel extends _$NewListViewModel {
  @override
  void build() {}

  /// Returns the new list's id. The shares go out once the server knows the list.
  @command
  Future<String> create({
    required String name,
    required String kind,
    String? description,
    List<String> assignees = const [],
    List<String> tags = const [],
    List<KanbanColumn>? columns,
    List<WriteShare> shares = const [],
  }) async {
    // Both taken before the first wait: a sheet only reads this ViewModel, and it
    // may be gone by the time the list is written.
    final access = ref.read(accessRepositoryProvider);
    final id = await ref
        .read(todoRepositoryProvider)
        .createList(
          name: name,
          kind: kind,
          description: description,
          assignees: assignees,
          tags: tags,
          columns: columns,
        );
    await access.queueShares(
      itemType: EntityTypes.todoList,
      itemId: id,
      shares: shares,
    );
    return id;
  }
}
