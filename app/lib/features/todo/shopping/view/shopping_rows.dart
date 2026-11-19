import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/common/wire.dart';
import '../../../../core/routing/item_navigation.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/ui/row_divider.dart';
import '../../../../domain/todo/todo_items.dart';
import '../../view/removable_row.dart';
import '../../view/todo_row.dart';
import '../shopping_view_model.dart';
import 'shopping_aisles.dart';

/// The rows, grouped by category. [preview]: a row opens its own preview, and rows
/// still move.
class ShoppingRows extends ConsumerWidget {
  const ShoppingRows({
    super.key,
    required this.listId,
    required this.state,
    this.sliver = false,
    this.preview = false,
    this.keyOf,
    this.expectBack,
  });

  final String listId;
  final ShoppingState state;
  final bool sliver;
  final bool preview;

  /// The key of a row — the one just added gets one to be scrolled to.
  final Key? Function(String id)? keyOf;

  /// Told the rows "Undo" brings back, so the list scrolls to them.
  final void Function(Iterable<String> ids)? expectBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ShoppingAisles(
      items: state.items,
      products: state.products,
      aisles: state.aisles,
      movable: state.writable,
      sliver: sliver,
      onAssignAisle: (productName, aisleId) => ref
          .read(shoppingViewModelProvider(listId).notifier)
          .assignAisle(productName, aisleId),
      onReposition: (item, {required others, required at}) => ref
          .read(shoppingViewModelProvider(listId).notifier)
          .reposition(item, others: others, at: at),
      // Held, a row's line is edited in place — not in a link's preview, and only
      // for whoever may write the list.
      onRename: state.writable && !preview
          ? (todo, text) => ref
                .read(shoppingViewModelProvider(listId).notifier)
                .renameItem(todo, text)
          : null,
      rowBuilder: (todo) => _DeletableRow(
        key: keyOf?.call(todo.id),
        listId: listId,
        todo: todo,
        expectBack: expectBack,
        // Held, the delete symbol deletes — not in a link's preview, and only for
        // whoever may write the list.
        deletable: state.writable && !preview,
        child: _LinedRow(
          child: TodoRowTile(
            todo: todo,
            shopping: true,
            deletable: state.writable && !preview,
            onToggle: state.mayCheckOff(todo)
                ? () => ref
                      .read(shoppingViewModelProvider(listId).notifier)
                      .setStatus(todo, todo.status != TodoStatuses.done)
                : null,
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
          ),
        ),
      ),
    );
  }
}

/// A shopping entry with the line under it that every row of a list has.
class _LinedRow extends StatelessWidget {
  const _LinedRow({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    mainAxisSize: .min,
    children: [child, const RowDivider()],
  );
}

/// A shopping row that its delete symbol can take away.
class _DeletableRow extends ConsumerWidget {
  const _DeletableRow({
    super.key,
    required this.listId,
    required this.todo,
    required this.deletable,
    required this.child,
    this.expectBack,
  });

  final String listId;
  final Todo todo;
  final bool deletable;
  final Widget child;
  final void Function(Iterable<String> ids)? expectBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!deletable) return child;
    return RemovableRow(
      onRemoved: () {
        ref.read(shoppingViewModelProvider(listId).notifier).deleteItem(todo);
        // The row is gone when "Undo" comes: it goes through the container.
        final container = ProviderScope.containerOf(context, listen: false);
        final expectBack = this.expectBack;
        showTodoDeletedSnackBar(
          context,
          title: todo.title,
          onUndo: () {
            expectBack?.call([todo.id]);
            container
                .read(shoppingViewModelProvider(listId).notifier)
                .undoDeleteItem(todo.id);
          },
        );
      },
      child: child,
    );
  }
}
