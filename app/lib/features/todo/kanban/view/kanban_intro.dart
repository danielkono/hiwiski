import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/routing/item_navigation.dart';
import '../../view/list_intro.dart';
import '../kanban_view_model.dart';

/// The list's description and archive mark above its board.
class KanbanIntro extends ConsumerWidget {
  const KanbanIntro({super.key, required this.listId, required this.state});

  final String listId;
  final KanbanState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListIntro(
    list: state.list,
    archivedBy: state.archivedBy,
    onRestore: state.mayChange
        ? () => ref
              .read(kanbanViewModelProvider(listId).notifier)
              .restore(state.list)
        : null,
    onOpenLink: (target) => openLinkTarget(context, ref, target),
    onToggleTask: state.writable
        ? (index) => ref
              .read(kanbanViewModelProvider(listId).notifier)
              .toggleDescriptionTask(state.list, index)
        : null,
  );
}
