import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../components/rich_text/view/rich_markdown.dart';
import '../../../../components/rich_text/view/rich_text_editor.dart';
import '../../../../components/rich_text/view/markdown_text_controller.dart';
import '../../../../core/common/date_patterns.dart';
import '../../../../core/common/wire.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/item_navigation.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/archived_banner.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../../../domain/common/item_ref.dart';
import '../todo_detail_view_model.dart';
import '../../view/todo_keys.dart';

/// The title and description of a task while it is edited: "Edit" in the header opens
/// them as fields on the page, and the header's "Save" reads them here.
class TodoDraft {
  TodoDraft({required String title, required String description})
    : title = TextEditingController(text: title),
      description = MarkdownTextController(text: description);

  final TextEditingController title;
  final MarkdownTextController description;

  void dispose() {
    title.dispose();
    description.dispose();
  }
}

/// What the task detail shows besides comments and info bar: the checkbox, the
/// description and the series' recent occurrences. A link's preview shows it as it is.
///
/// **The title is in the header, once.** It used to stand here a second time, 24 px
/// under the header's 30, with a pencil of its own.
///
/// [preview]: the box can be ticked and links followed; there is no header around a
/// preview, so the title stands here.
///
/// [draft]: the task is being edited — title and description are its fields.
class TodoBody extends ConsumerWidget {
  const TodoBody({
    super.key,
    required this.todoId,
    this.preview = false,
    this.draft,
  });

  final String todoId;
  final bool preview;
  final TodoDraft? draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(todoDetailViewModelProvider(todoId))
        .when(
          skipLoadingOnReload: true,
          loading: () => const SizedBox.shrink(),
          error: (error, _) => NoticeBar.failure(context, error: error),
          data: (state) => state == null
              ? const SizedBox.shrink()
              : _TodoDetailBody(
                  preview: preview,
                  todoId: todoId,
                  state: state,
                  draft: draft,
                ),
        );
  }
}

class _TodoDetailBody extends ConsumerWidget {
  const _TodoDetailBody({
    required this.preview,
    required this.todoId,
    required this.state,
    required this.draft,
  });

  final bool preview;
  final String todoId;
  final TodoDetailState state;
  final TodoDraft? draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final row = state.todo;

    final done = row.status == TodoStatuses.done;
    final editable = state.writable && !preview;
    final draft = this.draft;
    final titleStyle = context.texts.headlineSmall?.copyWith(fontWeight: .w600);
    final description = row.description ?? '';

    final checkbox = IconButton(
      icon: Icon(
        done ? HiwiskiSymbols.checkBox : HiwiskiSymbols.checkBoxOutlineBlank,
        fill: done ? 1 : 0,
        size: HiwiskiMetrics.icon28,
        color: context.scheme.primary,
      ),
      onPressed: state.mayCheckOff
          ? () => ref
                .read(todoDetailViewModelProvider(todoId).notifier)
                .setStatus(row, !done)
          : null,
      tooltip: l.todoDone,
    );

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        if (state.list.archivedAt case final archivedAt?) ...[
          // The list's mark: restoring happens there, not per task.
          ArchivedBanner(archivedAt: archivedAt, archivedBy: state.archivedBy),
          const SizedBox(height: HiwiskiMetrics.space16),
        ],
        if (draft != null) ...[
          // The room of the field's label, which reaches over the field.
          const SizedBox(height: HiwiskiMetrics.space8),
          TextField(
            key: TodoKeys.todoTitleField,
            controller: draft.title,
            autofocus: true,
            textInputAction: .next,
            decoration: InputDecoration(labelText: l.todoTitle),
          ),
          const SizedBox(height: HiwiskiMetrics.space12),
          // Written like a wiki page: Markdown with the insert bar, `#` suggesting
          // items, images onto the task.
          RichTextEditor(
            controller: draft.description,
            carrier: ItemRef.todo(row.id),
            fieldKey: TodoKeys.todoDescription,
            label: l.todoDescription,
            hint: l.linkHintDescription,
            minLines: 3,
          ),
        ] else ...[
          Row(
            children: [
              checkbox,
              const SizedBox(width: HiwiskiMetrics.space6),
              Expanded(
                child: preview
                    ? Text(
                        row.title,
                        style: titleStyle?.copyWith(
                          decoration: done ? TextDecoration.lineThrough : null,
                        ),
                      )
                    // Says what the box is: without the title beside it, a box
                    // alone would be a riddle.
                    : Text(l.todoDone, style: context.texts.bodyLarge),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: HiwiskiMetrics.space12),
            // Read like a wiki page: chips, images, boxes to tick.
            RichMarkdown(
              text: description,
              onOpen: (target) => openLinkTarget(context, ref, target),
              onToggleTask: editable
                  ? (index) => ref
                        .read(todoDetailViewModelProvider(todoId).notifier)
                        .toggleDescriptionTask(row, index)
                  : null,
            ),
          ],
        ],
        if ((row.rrule ?? '').isNotEmpty) ...[
          const SizedBox(height: HiwiskiMetrics.space20),
          _SeriesInstances(state: state),
        ],
      ],
    );
  }
}

/// "Series · recent occurrences" — per row an icon (done / skipped), date, who
/// and when.
class _SeriesInstances extends StatelessWidget {
  const _SeriesInstances({required this.state});

  final TodoDetailState state;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final locale = Localizations.localeOf(context).toString();
    final rows = state.occurrences;
    final scheme = context.scheme;

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Text(l.todoSeriesRecent, style: context.tokens.text.sectionLabel),
        const SizedBox(height: HiwiskiMetrics.space4),
        if (rows.isEmpty)
          Text(
            l.todoSeriesNone,
            style: context.texts.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        for (final occurrence in rows.take(5))
          Container(
            padding: const .symmetric(vertical: HiwiskiMetrics.space8),
            decoration: BoxDecoration(
              // The context is BoxBorder: abstract, a shorthand finds no constructor.
              // ignore: many_lints/prefer_shorthands_with_constructors
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(
                  occurrence.skipped
                      ? HiwiskiSymbols.remove
                      : HiwiskiSymbols.checkBox,
                  fill: occurrence.skipped ? 0 : 1,
                  size: HiwiskiMetrics.icon20,
                  color: occurrence.skipped
                      ? scheme.onSurfaceVariant
                      : scheme.primary,
                ),
                const SizedBox(width: HiwiskiMetrics.space12),
                Expanded(
                  child: Text(
                    DateFormat(
                      DatePatterns.weekdayDayMonth,
                      locale,
                    ).format(occurrence.occurrenceDate),
                    style: context.texts.bodyLarge,
                  ),
                ),
                Text(
                  occurrence.skipped
                      ? l.todoSkipped
                      : [
                          state.members[occurrence.doneBy]?.displayName,
                          if (occurrence.doneAt case final doneAt?)
                            DateFormat.Hm(locale).format(doneAt.toLocal()),
                        ].whereType<String>().join(' · '),
                  style: context.texts.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
