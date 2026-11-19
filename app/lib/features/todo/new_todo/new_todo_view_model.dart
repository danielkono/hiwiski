import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../app/stores.dart';
import '../../../core/api/generated/export.dart' hide Mutation;
import '../../../core/common/command.dart';
import '../../../domain/todo/todo_models.dart';

part 'new_todo_view_model.g.dart';

/// `create`, run by a view: it shows the command running and reacts to how it ended.
final createTodoMutation = Mutation<String>(label: 'newTodoViewModel.create');

/// "New task": the lists it can go on, who can be assigned, who creates it.
@immutable
class const NewTodoState({
  /// The lists a task can go on — not shopping lists, they take items from the
  /// quick entry.
  required final List<TodoListSummary> lists,
  required final Map<String, Member> members,
  required final Member? me,
});

@riverpod
Stream<List<TodoListSummary>> _lists(Ref ref) =>
    ref.watch(todoRepositoryProvider).watchLists();

@riverpod
Stream<List<Member>> _members(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchMembers();

@riverpod
class NewTodoViewModel extends _$NewTodoViewModel {
  @override
  Future<NewTodoState> build() async {
    // From the server — not waited for: offline it may never come.
    final members = ref.watch(_membersProvider).value ?? const <Member>[];
    final me = ref.watch(sessionProvider.select((s) => s.member));
    final lists = await ref.watch(_listsProvider.future);
    return NewTodoState(
      lists: [
        for (final summary in lists)
          if (!summary.isShopping) summary,
      ],
      members: {for (final member in members) member.id: member},
      me: me,
    );
  }

  /// Returns the new task's id.
  @command
  Future<String> create({
    required String listId,
    required String title,
    String? description,
    DateTime? dueDate,
    String? rrule,
    List<String> assignees = const [],
    List<String> tags = const [],
  }) => ref
      .read(todoRepositoryProvider)
      .createTodo(
        listId: listId,
        title: title,
        description: description,
        dueDate: dueDate,
        rrule: rrule,
        assignees: assignees,
        tags: tags,
      );
}
