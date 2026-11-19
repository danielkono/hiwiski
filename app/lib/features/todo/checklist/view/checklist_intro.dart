import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/routing/item_navigation.dart';
import '../../view/list_intro.dart';
import '../checklist_view_model.dart';

class ChecklistIntro extends ConsumerWidget {
  const ChecklistIntro({super.key, required this.listId, required this.state});

  final String listId;
  final ChecklistState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListIntro(
    list: state.list,
    archivedBy: state.archivedBy,
    onRestore: state.mayChange
        ? () => ref
              .read(checklistViewModelProvider(listId).notifier)
              .restore(state.list)
        : null,
    onOpenLink: (target) => openLinkTarget(context, ref, target),
    onToggleTask: state.writable
        ? (index) => ref
              .read(checklistViewModelProvider(listId).notifier)
              .toggleDescriptionTask(state.list, index)
        : null,
  );
}
