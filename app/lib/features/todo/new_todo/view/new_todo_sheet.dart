import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../components/assignees/view/assignees.dart';
import '../../../../components/rich_text/view/rich_text_editor.dart';
import '../../../../components/rich_text/view/markdown_text_controller.dart';
import '../../../../components/sharing/view/share_summary_builder.dart';
import '../../../../components/tags/view/tag_field.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/field_pair.dart';
import '../../../../core/ui/hiwiski_sheet.dart';
import '../../../../core/ui/loading_strip.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../../../core/ui/picker_field.dart';
import '../../../../core/ui/recurrence_dialog.dart';
import '../../../../domain/common/item_ref.dart';
import '../../../../domain/tags/tag.dart';
import '../../../../domain/todo/kanban.dart';
import '../../../../domain/todo/todo_models.dart';
import '../new_todo_view_model.dart';
import '../../view/todo_keys.dart';

/// "New task" as a sheet, like a new event: title · description · due
/// · repeat · list · assigned · sharing. [listId] preselects the list, [title] is what
/// the quick entry held. Answers whether a task was created.
///
/// **The share rows show what applies automatically**: "Ben · automatically ·
/// assigned", "Everyone · inherited from the list". The task's own
/// share can be set on the item after creation — before that the server does not know it.
Future<bool> showNewTodoSheet(
  BuildContext context, {
  String? listId,
  String title = '',
}) async =>
    await showHiwiskiSheet<bool>(
      context: context,
      title: L.of(context).todoNewTask,
      builder: (context) => NewTodoBody(listId: listId, title: title),
    ) ??
    false;

/// The form of [showNewTodoSheet].
class NewTodoBody extends ConsumerStatefulWidget {
  const NewTodoBody({super.key, this.listId, this.title = ''});

  final String? listId;
  final String title;

  @override
  ConsumerState<NewTodoBody> createState() => _NewTodoBodyState();
}

class _NewTodoBodyState extends ConsumerState<NewTodoBody> {
  late final _title = TextEditingController(text: widget.title);
  final _description = MarkdownTextController();
  final _descriptionFocus = FocusNode();
  late String? _listId = widget.listId;
  DateTime? _due;
  String? _rrule;
  final _assignees = <String>{};
  Set<String> _tags = {};
  bool _listTagsTaken = false;

  /// Set by a failed attempt — the field turns red and says why, instead of the button
  /// silently doing nothing.
  String? _titleError;
  String? _listError;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    final listId = _listId;
    final l = L.of(context);
    setState(() {
      _titleError = title.isEmpty ? l.validationRequired : null;
      _listError = listId == null ? l.validationRequired : null;
    });
    if (title.isEmpty || listId == null) return;
    final description = _description.text.trim();
    await createTodoMutation.run(
      ref,
      (tsx) => tsx
          .get(newTodoViewModelProvider.notifier)
          .create(
            listId: listId,
            title: title,
            description: description.isEmpty ? null : description,
            dueDate: _due,
            rrule: _isKanban(listId) ? null : _rrule,
            assignees: _assignees.toList(),
            tags: _tags.toList(),
          ),
    );
    // Stays where it was started — the list shows the new task, as after an
    // event.
    if (mounted) Navigator.of(context).pop(true);
  }

  /// A new task starts with its list's tags; switching the list swaps them and keeps
  /// the ones picked by hand.
  void _takeListTags(
    List<TodoListSummary> lists, {
    required String? from,
    required String? to,
  }) {
    String tagsOf(String? id) =>
        lists
            .where((summary) => summary.list.id == id)
            .firstOrNull
            ?.list
            .tags ??
        '';
    _tags = {..._tags}
      ..removeAll(tagIdsOf(tagsOf(from)))
      ..addAll(tagIdsOf(tagsOf(to)));
  }

  bool _isKanban(String listId) =>
      (ref.read(newTodoViewModelProvider).value?.lists ?? const [])
          .where((summary) => summary.list.id == listId)
          .firstOrNull
          ?.list
          .kind ==
      kindKanban;

  @override
  Widget build(BuildContext context) {
    return ref
        .watch(newTodoViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => const LoadingStrip(loading: true),
          error: (error, _) => NoticeBar.failure(context, error: error),
          data: (state) {
            final l = L.of(context);
            final locale = Localizations.localeOf(context).toString();
            final lists = state.lists;
            if (!_listTagsTaken && lists.isNotEmpty) {
              _listId ??= lists.first.list.id;
              _listTagsTaken = true;
              _takeListTags(lists, from: null, to: _listId);
            }
            final kanban =
                lists
                    .where((summary) => summary.list.id == _listId)
                    .firstOrNull
                    ?.list
                    .kind ==
                kindKanban;
            final members = state.members;
            final me = state.me;

            return Column(
              crossAxisAlignment: .stretch,
              children: [
                TextField(
                  controller: _title,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l.todoTitle,
                    errorText: _titleError,
                  ),
                  onChanged: (_) {
                    if (_titleError != null) {
                      setState(() => _titleError = null);
                    }
                  },
                ),
                const SizedBox(height: HiwiskiMetrics.space20),
                // Written like a wiki page, as in the task's detail
                // later; images once the task exists.
                RichTextEditor(
                  controller: _description,
                  focusNode: _descriptionFocus,
                  fieldKey: TodoKeys.todoDescription,
                  label: l.todoDescription,
                  hint: l.linkHintDescription,
                  minLines: 3,
                ),
                const SizedBox(height: HiwiskiMetrics.space20),
                FieldPair(
                  children: [
                    PickerField(
                      icon: HiwiskiSymbols.event,
                      label: l.todoDue,
                      value: switch (_due) {
                        null => l.todoNoDue,
                        final due => DateFormat.yMEd(locale).format(due),
                      },
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _due ?? clock.now(),
                          firstDate: DateTime(clock.now().year - 1),
                          lastDate: DateTime(clock.now().year + 10),
                        );
                        if (picked != null && mounted) {
                          setState(() => _due = picked);
                        }
                      },
                    ),
                    // A board has no repeats.
                    if (!kanban)
                      PickerField(
                        icon: HiwiskiSymbols.repeat,
                        label: l.todoRepeat,
                        value: describeRecurrence(
                          context,
                          _rrule,
                          _due ?? clock.now(),
                        ),
                        onTap: () async {
                          final result = await showRecurrenceDialog(
                            context: context,
                            rrule: _rrule,
                            start: _due ?? clock.now(),
                          );
                          if (result != null && mounted) {
                            setState(
                              () => _rrule = result.isEmpty ? null : result,
                            );
                          }
                        },
                      ),
                  ],
                ),
                const SizedBox(height: HiwiskiMetrics.space20),
                DropdownButtonFormField<String>(
                  // A long list name shortens instead of running past
                  // the edge.
                  isExpanded: true,
                  initialValue: _listId,
                  decoration: InputDecoration(
                    labelText: l.todoList,
                    prefixIcon: const Icon(HiwiskiSymbols.checklist),
                    errorText: _listError,
                    // Without a list there is nowhere to put the task.
                    helperText: lists.isEmpty ? l.todoNoListYet : null,
                  ),
                  items: [
                    for (final summary in lists)
                      DropdownMenuItem(
                        value: summary.list.id,
                        child: Text(summary.list.name, overflow: .ellipsis),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _takeListTags(lists, from: _listId, to: value);
                    _listId = value;
                    _listError = null;
                  }),
                ),
                const SizedBox(height: HiwiskiMetrics.space20),
                AssigneeChips(
                  selected: _assignees,
                  hint: l.todoAssignedHint,
                  onToggle: (id) => setState(
                    () => _assignees.contains(id)
                        ? _assignees.remove(id)
                        : _assignees.add(id),
                  ),
                ),
                const SizedBox(height: HiwiskiMetrics.space20),
                TagField(
                  selected: _tags,
                  onChanged: (next) => setState(() => _tags = next),
                ),
                const SizedBox(height: HiwiskiMetrics.space20),
                Text(l.shareTitle, style: context.tokens.text.sectionLabel),
                const SizedBox(height: HiwiskiMetrics.space4),
                if (me != null)
                  _ShareLine(
                    icon: HiwiskiSymbols.person,
                    label: l.youSuffix(me.displayName),
                    mode: l.shareOwner,
                  ),
                for (final id in _assignees.where((id) => id != me?.id))
                  _ShareLine(
                    icon: HiwiskiSymbols.assignmentInd,
                    label: members[id]?.displayName ?? '—',
                    mode: l.shareAssigned,
                  ),
                if (_listId case final listId?)
                  ShareSummaryBuilder(
                    item: ItemRef.todoList(listId),
                    builder: (context, icon, text) => _ShareLine(
                      icon: icon,
                      label: text,
                      mode: l.shareFromList,
                    ),
                  ),
                SheetActions(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l.actionCancel),
                    ),
                    FilledButton(
                      key: TodoKeys.newTodoCreate,
                      onPressed: _create,
                      child: Text(l.tagCreate),
                    ),
                  ],
                ),
              ],
            );
          },
        );
  }
}

class _ShareLine extends StatelessWidget {
  const _ShareLine({
    required this.icon,
    required this.label,
    required this.mode,
  });

  final IconData icon;
  final String label;
  final String mode;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: HiwiskiMetrics.formRowHeight),
    child: Row(
      children: [
        Icon(
          icon,
          size: HiwiskiMetrics.icon22,
          color: context.scheme.onSurfaceVariant,
        ),
        const SizedBox(width: HiwiskiMetrics.space14),
        Expanded(child: Text(label, style: context.texts.bodyLarge)),
        const SizedBox(width: HiwiskiMetrics.space8),
        // "Everyone · inherited from the list" is wider than a phone leaves it:
        // it wraps instead of running past the edge.
        Flexible(
          child: Text(
            mode,
            textAlign: .end,
            style: context.texts.bodyMedium?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
}
