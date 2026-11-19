import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/new_row_reveal.dart';
import '../../../../core/common/wire.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/ui/drag_auto_scroll.dart';
import '../../../../core/ui/info_action.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../../../domain/common/change.dart';
import '../../view/kanban_columns_editor.dart';
import '../../view/list_editor.dart';
import '../../view/list_frame.dart';
import '../../view/list_info.dart';
import '../../view/list_intro.dart';
import '../../view/list_parts.dart';
import '../../view/quick_entry_bar.dart';
import '../../view/removable_row.dart';
import '../../view/todo_keys.dart';
import '../checklist_view_model.dart';
import 'checklist_intro.dart';
import 'checklist_row.dart';
import '../../../../core/ui/states.dart';

/// A task list: rows with due date and assignment, the quick entry at the bottom.
class ChecklistScreen extends ConsumerWidget {
  const ChecklistScreen({super.key, required this.listId});

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
        .watch(checklistViewModelProvider(listId))
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(header: header, error: error),
          // Deleted, or no longer shared: it says so instead of an empty page.
          data: (state) => state == null
              ? HiwiskiPage(
                  header: header,
                  body: EmptyState(
                    icon: HiwiskiSymbols.checklist,
                    message: L.of(context).stateGone,
                  ),
                )
              : _ChecklistPage(listId: listId, state: state),
        );
  }
}

class _ChecklistPage extends ConsumerStatefulWidget {
  const _ChecklistPage({required this.listId, required this.state});

  final String listId;
  final ChecklistState state;

  @override
  ConsumerState<_ChecklistPage> createState() => _ChecklistPageState();
}

class _ChecklistPageState extends ConsumerState<_ChecklistPage> {
  /// Whether name and description are open as fields above the rows.
  bool _editing = false;

  /// The fields open on the page: the header's "Save" reads them through this.
  final _editor = GlobalKey<ListEditorState>();

  final _scroll = ScrollController();
  final _newRow = NewRowReveal();

  /// Scrolls the rows while one is held near the edge.
  final _autoScroll = DragAutoScroll();

  @override
  void dispose() {
    _autoScroll.stop();
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
          .read(checklistViewModelProvider(listId).notifier)
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
      ref.read(checklistViewModelProvider(listId).notifier).deleteDone(done);
      // The rows are gone when "Undo" comes: it goes through the container.
      final container = ProviderScope.containerOf(context, listen: false);
      final ids = [for (final todo in done) todo.id];
      showDoneDeletedSnackBar(
        context,
        count: done.length,
        onUndo: () {
          _newRow.expectBack(ids);
          container
              .read(checklistViewModelProvider(listId).notifier)
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
            ref.read(checklistViewModelProvider(listId).notifier).archive(list),
        onRestore: () =>
            ref.read(checklistViewModelProvider(listId).notifier).restore(list),
        onDelete: () =>
            ref.read(checklistViewModelProvider(listId).notifier).delete(list),
        extra: [
          // Once and only in this direction: a task list may become a board.
          if (state.writable && list.kind == ListKinds.standard)
            Padding(
              padding: const .only(top: HiwiskiMetrics.space4),
              child: InfoAction(
                key: TodoKeys.kanbanConvert,
                icon: HiwiskiSymbols.viewKanban,
                label: l.kanbanConvert,
                onTap: () => showConvertToKanbanSheet(
                  context,
                  cards: state.items,
                  onConvert: (columns) => ref
                      .read(checklistViewModelProvider(listId).notifier)
                      .convertToKanban(list, columns, state.items),
                ),
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
              .read(checklistViewModelProvider(listId).notifier)
              .untickAll(state.done),
          onDeleteDone: deleteDone,
        ),
        (false, true) => ChecklistIntro(listId: listId, state: state),
        (false, false) => null,
      },
      empty: state.items.isEmpty,
      emptyIcon: HiwiskiSymbols.checklist,
      controller: _scroll,
      rows: SliverList.builder(
        itemCount: state.items.length,
        itemBuilder: (context, index) => ChecklistRow(
          key: _newRow.keyOf(state.items[index].id),
          listId: listId,
          state: state,
          todo: state.items[index],
          expectBack: _newRow.expectBack,
          autoScroll: _autoScroll,
        ),
      ),
      quickEntry: !state.writable
          ? null
          : ({required docked}) => QuickEntryBar(
              listId: listId,
              listTags: list.tags,
              shopping: false,
              docked: docked,
              onAdding: () =>
                  _newRow.expect([for (final todo in state.items) todo.id]),
              onSubmit: (entry, tags) {
                _newRow.expect([for (final todo in state.items) todo.id]);
                return ref
                    .read(checklistViewModelProvider(listId).notifier)
                    .add(list, title: entry.title, tags: tags);
              },
            ),
    );
  }
}
