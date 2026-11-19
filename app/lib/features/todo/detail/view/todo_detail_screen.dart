import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../components/comments/view/comment_list.dart';
import '../../../../components/item_info/view/item_info.dart';
import '../../../../core/common/date_patterns.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/item_navigation.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/shell/breakpoints.dart';
import '../../../../core/ui/info_bar.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/archive_ui.dart';
import '../../../../core/ui/color_tokens.dart';
import '../../../../core/ui/edit_actions.dart';
import '../../../../core/ui/info_delete_section.dart';
import '../../../../core/ui/info_property.dart';
import '../../../../core/ui/page_header.dart';
import '../../../../core/ui/recurrence_dialog.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../../../core/ui/states.dart';
import '../../../../domain/catalog/catalog_product.dart';
import '../../../../domain/common/change.dart';
import '../../../../domain/common/item_ref.dart';
import '../../../../domain/todo/kanban.dart';
import '../../view/aisle_ui.dart';
import '../../view/todo_keys.dart';
import '../todo_detail_view_model.dart';
import 'todo_body.dart';

/// The task detail.
///
/// The title in the header, below it the checkbox and the description — **with
/// reference chips**, because a `#WIKI-3` in the description is a reference and not
/// text. "Edit" turns title and description into fields on the page, with "Cancel"
/// and "Save" where "Edit" was. For series "Series · recent occurrences", below that the comments.
///
/// Info bar: due, repeat, list, assigned, tags, sharing, references,
/// info, history.
class TodoDetailScreen extends ConsumerWidget {
  const TodoDetailScreen({super.key, required this.todoId});

  final String todoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    // No title to show yet, but a way back.
    final header = PageHeader(
      title: '',
      onBack: () => goBack(context, () => const TodoRoute().go(context)),
    );
    return ref
        .watch(todoDetailViewModelProvider(todoId))
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(header: header, error: error),
          data: (state) => state == null
              ? HiwiskiPage(
                  header: header,
                  body: EmptyState(
                    icon: HiwiskiSymbols.checklist,
                    message: l.stateGone,
                  ),
                )
              : _TodoDetailPage(todoId: todoId, state: state),
        );
  }
}

class _TodoDetailPage extends ConsumerStatefulWidget {
  const _TodoDetailPage({required this.todoId, required this.state});

  final String todoId;
  final TodoDetailState state;

  @override
  ConsumerState<_TodoDetailPage> createState() => _TodoDetailPageState();
}

class _TodoDetailPageState extends ConsumerState<_TodoDetailPage> {
  /// Set while the task is edited: its title and description as fields.
  TodoDraft? _draft;

  @override
  void dispose() {
    _draft?.dispose();
    super.dispose();
  }

  void _startEditing() {
    final row = widget.state.todo;
    setState(
      () => _draft = TodoDraft(
        title: row.title,
        description: row.description ?? '',
      ),
    );
  }

  void _stopEditing() {
    final draft = _draft;
    setState(() => _draft = null);
    // After the frame: the fields still hold the controllers until they are gone.
    WidgetsBinding.instance.addPostFrameCallback((_) => draft?.dispose());
  }

  void _save() {
    final draft = _draft;
    if (draft == null) return;
    final row = widget.state.todo;
    final title = draft.title.text.trim();
    final description = draft.description.text.trim();
    final titleChanged = title.isNotEmpty && title != row.title;
    final descriptionChanged = description != (row.description ?? '');
    if (titleChanged || descriptionChanged) {
      // Written on the device; nothing here waits for the server.
      unawaited(
        ref
            .read(todoDetailViewModelProvider(widget.todoId).notifier)
            .edit(
              row,
              // An empty title keeps the old one.
              title: titleChanged ? title : null,
              description: descriptionChanged
                  ? Change(description.isEmpty ? null : description)
                  : null,
            ),
      );
    }
    _stopEditing();
  }

  @override
  Widget build(BuildContext context) {
    final todoId = widget.todoId;
    final state = widget.state;
    final l = L.of(context);
    final padding = Breakpoint.of(context).pagePadding;
    final row = state.todo;

    final locale = Localizations.localeOf(context).toString();
    final wide = InfoBar.besideContent(context);
    final list = state.list;
    final writable = state.writable;
    final column = state.column;
    final aisle = state.aisle;

    Future<void> pickColumn(Offset at) async {
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox;
      final picked = await showMenu<KanbanColumn>(
        context: context,
        position: RelativeRect.fromRect(
          at & Size.zero,
          Offset.zero & overlay.size,
        ),
        items: [
          for (final option in state.columns)
            PopupMenuItem(
              value: option,
              child: Row(
                children: [
                  Container(
                    width: HiwiskiMetrics.dotSmall,
                    height: HiwiskiMetrics.dotSmall,
                    decoration: BoxDecoration(
                      color: context.tokens.accent(accentOf(option.colorToken)),
                      shape: .circle,
                    ),
                  ),
                  const SizedBox(width: HiwiskiMetrics.space10),
                  Text(option.name),
                  if (option.id == column?.id) ...[
                    const Spacer(),
                    const Icon(
                      HiwiskiSymbols.check,
                      size: HiwiskiMetrics.icon18,
                    ),
                  ],
                ],
              ),
            ),
        ],
      );
      if (picked == null || picked.id == column?.id || !context.mounted) {
        return;
      }
      await ref
          .read(todoDetailViewModelProvider(todoId).notifier)
          .moveTo(picked);
    }

    Future<void> pickDue() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: row.dueDate ?? clock.now(),
        firstDate: DateTime(clock.now().year - 5),
        lastDate: DateTime(clock.now().year + 10),
      );
      if (picked == null || !context.mounted) return;
      await ref
          .read(todoDetailViewModelProvider(todoId).notifier)
          .edit(row, dueDate: Change(picked));
    }

    // **Recurring tasks via the same component**: the same dialog
    // as on the event. A second, poorer dialog just for tasks would be exactly an earlier version
    // mistake all over again.
    Future<void> pickRepeat() async {
      final result = await showRecurrenceDialog(
        context: context,
        rrule: row.rrule,
        start: row.dueDate ?? clock.now(),
      );
      if (result == null || !context.mounted) return;
      await ref
          .read(todoDetailViewModelProvider(todoId).notifier)
          .edit(row, rrule: Change(result.isEmpty ? null : result));
    }

    final infoBar = ItemInfo(
      item: ItemRef.todo(row.id),
      editable: writable,
      properties: [
        if (state.shopping)
          Builder(
            builder: (context) => InfoProperty(
              key: TodoKeys.todoAisle,
              label: l.todoAisle,
              value: aisleLabel(l, aisle),
              onTap: writable
                  ? () {
                      final box = context.findRenderObject() as RenderBox;
                      pickAisle(
                        context,
                        at: box.localToGlobal(Offset(0, box.size.height)),
                        productName: catalogNameFor(
                          row.title,
                          row.productId,
                          state.products,
                        ),
                        current: aisle,
                        aisles: state.aisles,
                        createAisle: (name) => createAisleForTodoMutation.run(
                          ref,
                          (tsx) => tsx
                              .get(todoDetailViewModelProvider(todoId).notifier)
                              .createAisle(name),
                        ),
                        assignAisle: ref
                            .read(todoDetailViewModelProvider(todoId).notifier)
                            .assignAisle,
                      );
                    }
                  : null,
            ),
          )
        else
          InfoProperty(
            label: l.todoDue,
            value: switch (row.dueDate) {
              null => l.todoNoDue,
              final due => DateFormat(
                DatePatterns.weekdayDayMonth,
                locale,
              ).format(due),
            },
            onTap: writable ? pickDue : null,
          ),
        if (column != null)
          Builder(
            builder: (context) => InfoProperty(
              key: TodoKeys.todoColumn,
              label: l.kanbanColumn,
              value: column.name,
              dot: context.tokens.accent(accentOf(column.colorToken)),
              onTap: state.mayCheckOff
                  ? () {
                      final box = context.findRenderObject() as RenderBox;
                      pickColumn(box.localToGlobal(Offset(0, box.size.height)));
                    }
                  : null,
            ),
          )
        else if (!state.shopping)
          InfoProperty(
            label: l.todoRepeat,
            value: describeRecurrence(
              context,
              row.rrule,
              row.dueDate ?? clock.now(),
            ),
            onTap: writable ? pickRepeat : null,
          ),
        InfoProperty(label: l.todoList, value: list.name),
      ],
      actions: [
        if (writable)
          InfoDeleteSection(
            label: l.todoDelete,
            confirmTitle: l.todoDeleteConfirm,
            onDelete: () async {
              await ref
                  .read(todoDetailViewModelProvider(todoId).notifier)
                  .delete(row);
              if (context.mounted) {
                TodoListRoute(listId: row.listId).go(context);
              }
            },
          ),
      ],
    );

    final content = ListView(
      padding: padding.add(const .only(bottom: HiwiskiMetrics.space32)),
      children: [
        TodoBody(todoId: todoId, draft: _draft),
        const SizedBox(height: HiwiskiMetrics.space24),
        CommentList(item: ItemRef.todo(row.id), readOnly: state.archived),
        if (!wide) infoBar,
      ],
    );

    return HiwiskiPage(
      header: PageHeader(
        title: row.title,
        // "TD-14 · Haushalt" — the citable key, then the list as a link to it.
        // Created offline means: no key yet.
        entityKey: row.entityKey ?? l.todoNoKey,
        crumbs: [
          HeaderCrumb(
            label: list.name,
            onTap: () => TodoListRoute(listId: row.listId).go(context),
          ),
        ],
        onBack: () => goBack(
          context,
          () => TodoListRoute(listId: row.listId).go(context),
        ),
        trailing: [
          if (state.archived) const ArchivedChip(),
          if (writable)
            EditActions(
              editing: _draft != null,
              onEdit: _startEditing,
              onSave: _save,
              onCancel: _stopEditing,
            ),
        ],
      ),
      body: Row(
        crossAxisAlignment: .stretch,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth:
                      HiwiskiMetrics.contentMaxWidth +
                      2 * HiwiskiMetrics.space32,
                ),
                child: content,
              ),
            ),
          ),
          if (wide) infoBar,
        ],
      ),
    );
  }
}
