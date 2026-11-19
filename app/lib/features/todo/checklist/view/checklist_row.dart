import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/common/wire.dart';
import '../../../../core/routing/item_navigation.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../domain/todo/todo_items.dart';
import '../../../../core/ui/drag_auto_scroll.dart';
import '../../../../core/ui/item_draggable.dart';
import '../../../../core/ui/renamable_row.dart';
import '../../../../core/ui/row_divider.dart';
import '../../view/removable_row.dart';
import '../../view/row_drop_slot.dart';
import '../../view/todo_meta.dart';
import '../../view/todo_row.dart';
import '../checklist_view_model.dart';

class ChecklistRow extends ConsumerWidget {
  const ChecklistRow({
    super.key,
    required this.listId,
    required this.state,
    required this.todo,
    this.preview = false,
    this.expectBack,
    this.autoScroll,
  });

  final String listId;
  final ChecklistState state;
  final Todo todo;
  final bool preview;

  /// Told the rows "Undo" brings back, so the list scrolls to them.
  final void Function(Iterable<String> ids)? expectBack;

  /// Scrolls the list while a row is held near its edge — where rows can be
  /// dragged into another place; `null` where they cannot.
  final DragAutoScroll? autoScroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Held, the delete symbol deletes — with a moment to take it back. Not in a
    // link's preview, and only for whoever may write the list.
    final deletable = state.writable && !preview;
    final tile = TodoRowTile(
      todo: todo,
      shopping: false,
      deletable: deletable,
      meta: todoMeta(context, todo, state.members),
      onToggle: state.mayCheckOff(todo)
          ? () => ref
                .read(checklistViewModelProvider(listId).notifier)
                .setStatus(todo, todo.status != TodoStatuses.done)
          : null,
      // In a link's preview a tap opens the task's preview, not its page.
      onOpen: preview
          ? () => openPreviewOf(
              context,
              ref,
              itemType: EntityTypes.todo,
              itemId: todo.id,
            )
          : () => TodoDetailRoute(
              listId: todo.listId,
              todoId: todo.id,
            ).go(context),
    );
    final row = Column(
      crossAxisAlignment: .stretch,
      children: [tile, const RowDivider()],
    );
    if (!deletable) return row;
    final renamable = RenamableRow(
      onRenamed: (title) => ref
          .read(checklistViewModelProvider(listId).notifier)
          .renameItem(todo, title),
      child: switch (autoScroll) {
        null => row,
        final autoScroll => ItemDraggable<Todo>(
          data: todo,
          feedback: SizedBox(
            width: HiwiskiMetrics.dragFeedbackWidth,
            child: Material(
              elevation: HiwiskiMetrics.elevationDrag,
              borderRadius: const .all(.circular(HiwiskiMetrics.radiusMenu)),
              child: tile,
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: row),
          onDragStarted: () {},
          onDragUpdate: (details) =>
              autoScroll.update(context, details.globalPosition),
          onDragDone: autoScroll.stop,
          child: row,
        ),
      },
    );
    return RemovableRow(
      onRemoved: () {
        ref.read(checklistViewModelProvider(listId).notifier).deleteItem(todo);
        // The row is gone when "Undo" comes: it goes through the container.
        final container = ProviderScope.containerOf(context, listen: false);
        final expectBack = this.expectBack;
        showTodoDeletedSnackBar(
          context,
          title: todo.title,
          onUndo: () {
            expectBack?.call([todo.id]);
            container
                .read(checklistViewModelProvider(listId).notifier)
                .undoDeleteItem(todo.id);
          },
        );
      },
      child: autoScroll == null
          ? renamable
          : RowDropSlot(
              row: todo,
              onDrop: (dragged, {required before}) => ref
                  .read(checklistViewModelProvider(listId).notifier)
                  .moveItem(dragged, onRow: todo, before: before),
              child: renamable,
            ),
    );
  }
}
