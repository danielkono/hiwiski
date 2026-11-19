import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/common/wire.dart';
import '../../../../core/routing/item_navigation.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/ui/page_header.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../../../domain/todo/kanban.dart';
import '../../checklist/view/checklist_screen.dart';
import '../../kanban/view/kanban_screen.dart';
import '../../shopping/view/shopping_screen.dart';
import '../todo_list_view_model.dart';

/// A list: tasks, shopping or a Kanban board — each kind its own screen with its own
/// ViewModel; the address is the same.
class TodoListScreen extends ConsumerWidget {
  const TodoListScreen({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = PageHeader(
      title: '',
      onBack: () => goBack(context, () => const TodoRoute().go(context)),
    );
    return ref
        .watch(todoListViewModelProvider(listId))
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(header: header, error: error),
          data: (kind) => switch (kind) {
            null => HiwiskiPage(header: header, body: const SizedBox.shrink()),
            ListKinds.shopping => ShoppingScreen(listId: listId),
            kindKanban => KanbanScreen(listId: listId),
            _ => ChecklistScreen(listId: listId),
          },
        );
  }
}
