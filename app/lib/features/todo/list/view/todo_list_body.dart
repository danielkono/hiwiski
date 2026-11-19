import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/common/wire.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../../../domain/todo/kanban.dart';
import '../../checklist/view/checklist_preview.dart';
import '../../kanban/view/kanban_preview.dart';
import '../../shopping/view/shopping_preview.dart';
import '../todo_list_view_model.dart';

/// What a list shows between its header and the quick entry, without the info area —
/// a link's preview shows it as it is: boxes can be ticked, rows
/// and cards moved and links followed; nothing new is added.
class TodoListBody extends ConsumerWidget {
  const TodoListBody({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(todoListViewModelProvider(listId))
      .when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (error, _) => NoticeBar.failure(context, error: error),
        data: (kind) => switch (kind) {
          null => const SizedBox.shrink(),
          ListKinds.shopping => ShoppingPreview(listId: listId),
          kindKanban => KanbanPreview(listId: listId),
          _ => ChecklistPreview(listId: listId),
        },
      );
}
