import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/shell/breakpoints.dart';
import '../../../../core/ui/info_bar.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/ui/info_property.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../../../domain/common/change.dart';
import '../../view/kanban_columns_editor.dart';
import '../../view/list_editor.dart';
import '../../view/list_info.dart';
import '../../view/list_intro.dart';
import '../../view/list_parts.dart';
import '../../view/todo_keys.dart';
import '../kanban_view_model.dart';
import 'kanban_intro.dart';
import 'kanban_state_board.dart';
import '../../../../core/ui/states.dart';
import '../../../../core/theme/hiwiski_symbols.dart';

/// A board's page: the columns fill it; the info area sits beside them on a wide
/// screen and follows below on the phone — a scroll away, not behind a button.
class KanbanScreen extends ConsumerWidget {
  const KanbanScreen({super.key, required this.listId});

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
        .watch(kanbanViewModelProvider(listId))
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(header: header, error: error),
          // Deleted, or no longer shared: it says so instead of an empty page.
          data: (state) => switch (state) {
            null => HiwiskiPage(
              header: header,
              body: EmptyState(
                icon: HiwiskiSymbols.viewKanban,
                message: L.of(context).stateGone,
              ),
            ),
            KanbanState(columns: []) => HiwiskiPage(
              header: header,
              body: const SizedBox.shrink(),
            ),
            _ => _KanbanPage(listId: listId, state: state),
          },
        );
  }
}

class _KanbanPage extends ConsumerStatefulWidget {
  const _KanbanPage({required this.listId, required this.state});

  final String listId;
  final KanbanState state;

  @override
  ConsumerState<_KanbanPage> createState() => _KanbanPageState();
}

class _KanbanPageState extends ConsumerState<_KanbanPage> {
  /// Whether name and description are open as fields above the board.
  bool _editing = false;

  /// The fields open on the page: the header's "Save" reads them through this.
  final _editor = GlobalKey<ListEditorState>();

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final listId = widget.listId;
    final state = widget.state;
    final list = state.list;
    final padding = Breakpoint.of(context).pagePadding;
    final wide = InfoBar.besideContent(context);

    Future<void> save({
      required String name,
      required String? description,
    }) async {
      setState(() => _editing = false);
      await ref
          .read(kanbanViewModelProvider(listId).notifier)
          .rename(
            list,
            name: name.isNotEmpty && name != list.name ? name : null,
            description: description != list.description
                ? Change(description)
                : null,
          );
    }

    final info = ListInfo(
      list: list,
      entries: state.items.length,
      open: state.open,
      writable: state.writable,
      mayChange: state.mayChange,
      mayDelete: state.mayDelete,
      onArchive: () =>
          ref.read(kanbanViewModelProvider(listId).notifier).archive(list),
      onRestore: () =>
          ref.read(kanbanViewModelProvider(listId).notifier).restore(list),
      onDelete: () =>
          ref.read(kanbanViewModelProvider(listId).notifier).delete(list),
      extra: [
        InfoProperty(
          key: TodoKeys.kanbanColumns,
          label: l.kanbanColumns,
          value: state.columns.map((column) => column.name).join(' · '),
          onTap: state.writable
              ? () => showEditColumnsSheet(
                  context,
                  list: list,
                  cards: state.items,
                  onSave: (columns) => ref
                      .read(kanbanViewModelProvider(listId).notifier)
                      .updateColumns(list, columns, state.items),
                )
              : null,
        ),
      ],
    );
    final board = KanbanStateBoard(
      state: state,
      padding: padding.copyWith(top: 0, bottom: HiwiskiMetrics.space20),
    );

    return HiwiskiPage(
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
      body: Column(
        crossAxisAlignment: .stretch,
        children: [
          // A board has no boxes to untick: only name and description.
          if (_editing && state.writable)
            Padding(
              padding: padding,
              child: ListEditor(
                key: _editor,
                list: list,
                done: 0,
                onSave: save,
              ),
            )
          else if (ListIntro.shows(list))
            Padding(
              padding: padding,
              child: KanbanIntro(listId: listId, state: state),
            ),
          Expanded(
            child: wide
                ? Row(
                    crossAxisAlignment: .stretch,
                    children: [
                      Expanded(child: board),
                      info,
                    ],
                  )
                : LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: .stretch,
                        children: [
                          SizedBox(height: constraints.maxHeight, child: board),
                          Padding(padding: padding, child: info),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
