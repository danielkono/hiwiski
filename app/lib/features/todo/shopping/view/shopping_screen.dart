import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/new_row_reveal.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/ui/info_action.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../../../domain/common/change.dart';
import '../../view/list_editor.dart';
import '../../view/list_frame.dart';
import '../../view/list_info.dart';
import '../../view/list_intro.dart';
import '../../view/list_parts.dart';
import '../../view/quick_entry_bar.dart';
import '../../view/removable_row.dart';
import '../../view/todo_keys.dart';
import '../shopping_view_model.dart';
import 'shopping_intro.dart';
import 'shopping_rows.dart';
import '../../../../core/ui/states.dart';

/// A shopping list: **grouped by category**, heading in `pri`, in the family's order;
/// rows are dragged between them. The amount in bold
/// before the product.
class ShoppingScreen extends ConsumerWidget {
  const ShoppingScreen({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = ListHeader(
      context,
      list: null,
      open: 0,
      writable: false,
      onEdit: () {},
    );
    return ref
        .watch(shoppingViewModelProvider(listId))
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(header: header, error: error),
          // Deleted, or no longer shared: it says so instead of an empty page.
          data: (state) => state == null
              ? HiwiskiPage(
                  header: header,
                  body: EmptyState(
                    icon: HiwiskiSymbols.shoppingCart,
                    message: L.of(context).stateGone,
                  ),
                )
              : _ShoppingPage(listId: listId, state: state),
        );
  }
}

class _ShoppingPage extends ConsumerStatefulWidget {
  const _ShoppingPage({required this.listId, required this.state});

  final String listId;
  final ShoppingState state;

  @override
  ConsumerState<_ShoppingPage> createState() => _ShoppingPageState();
}

class _ShoppingPageState extends ConsumerState<_ShoppingPage> {
  /// Whether name and description are open as fields above the rows.
  bool _editing = false;

  /// The fields open on the page: the header's "Save" reads them through this.
  final _editor = GlobalKey<ListEditorState>();

  final _scroll = ScrollController();
  final _newRow = NewRowReveal();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final listId = widget.listId;
    final state = widget.state;
    final list = state.list;
    _newRow.reveal([
      for (final todo in state.items) todo.id,
    ], position: () => _scroll.hasClients ? _scroll.position : null);

    Future<void> save({
      required String name,
      required String? description,
    }) async {
      setState(() => _editing = false);
      await ref
          .read(shoppingViewModelProvider(listId).notifier)
          .rename(
            list,
            name: name.isNotEmpty && name != list.name ? name : null,
            description: description != list.description
                ? Change(description)
                : null,
          );
    }

    void deleteDone() {
      final done = state.done;
      ref.read(shoppingViewModelProvider(listId).notifier).deleteDone(done);
      // The rows are gone when "Undo" comes: it goes through the container.
      final container = ProviderScope.containerOf(context, listen: false);
      final ids = [for (final todo in done) todo.id];
      showDoneDeletedSnackBar(
        context,
        count: done.length,
        onUndo: () {
          _newRow.expectBack(ids);
          container
              .read(shoppingViewModelProvider(listId).notifier)
              .undoDeleteItems(ids);
        },
      );
    }

    return ListFrame(
      header: ListHeader(
        context,
        list: list,
        open: state.open,
        writable: state.writable,
        editing: _editing,
        onEdit: () => setState(() => _editing = true),
        onSave: () => _editor.currentState?.save(),
        onCancel: () => setState(() => _editing = false),
      ),
      info: ListInfo(
        list: list,
        entries: state.items.length,
        open: state.open,
        writable: state.writable,
        mayChange: state.mayChange,
        mayDelete: state.mayDelete,
        onArchive: () =>
            ref.read(shoppingViewModelProvider(listId).notifier).archive(list),
        onRestore: () =>
            ref.read(shoppingViewModelProvider(listId).notifier).restore(list),
        onDelete: () =>
            ref.read(shoppingViewModelProvider(listId).notifier).delete(list),
        extra: [
          // The family's categories, for every shopping list at once.
          if (state.writable)
            Padding(
              padding: const .only(top: HiwiskiMetrics.space4),
              child: InfoAction(
                key: TodoKeys.aisles,
                icon: HiwiskiSymbols.category,
                label: l.aislesEdit,
                onTap: () => const CategoriesRoute().go(context),
              ),
            ),
        ],
      ),
      intro: switch ((_editing && state.writable, ListIntro.shows(list))) {
        (true, _) => ListEditor(
          key: _editor,
          list: list,
          done: state.done.length,
          onSave: save,
          onUntickAll: () => ref
              .read(shoppingViewModelProvider(listId).notifier)
              .untickAll(state.done),
          onDeleteDone: deleteDone,
        ),
        (false, true) => ShoppingIntro(listId: listId, state: state),
        (false, false) => null,
      },
      empty: state.items.isEmpty,
      emptyIcon: HiwiskiSymbols.shoppingCart,
      controller: _scroll,
      rows: ShoppingRows(
        listId: listId,
        state: state,
        sliver: true,
        keyOf: _newRow.keyOf,
        expectBack: _newRow.expectBack,
      ),
      quickEntry: !state.writable
          ? null
          : ({required docked}) => QuickEntryBar(
              listId: listId,
              listTags: list.tags,
              shopping: true,
              docked: docked,
              onSubmit: (entry, tags) {
                _newRow.expect([for (final todo in state.items) todo.id]);
                return ref
                    .read(shoppingViewModelProvider(listId).notifier)
                    .add(
                      list,
                      title: entry.title,
                      amount: entry.amount,
                      unit: entry.unit,
                      tags: tags,
                    );
              },
            ),
    );
  }
}
