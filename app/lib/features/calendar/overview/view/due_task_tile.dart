import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/row_chevron.dart';
import '../../../../core/ui/row_divider.dart';
import '../../../../domain/calendar/due_task.dart';
import '../../view/calendar_keys.dart';
import '../calendar_overview_view_model.dart';

/// A task due that day, among the events — **the row it is in its own list**: the
/// same box to tick, the same title and meta line, the arrow and the line below. It
/// used to be a card with another box in another colour, and the same task looked
/// like two things. A tap opens the task; the box ticks it off right here.
///
/// [framed] is for where the task stands alone and not in a list — beside others in
/// the week's strip: an outline then, and neither arrow nor line.
class DueTaskTile extends ConsumerWidget {
  const DueTaskTile({super.key, required this.task, this.framed = false});

  final DueTask task;
  final bool framed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final scheme = context.scheme;
    final todo = task.todo;
    final meta = [l.calTask, task.listName, ?todo.dueTime].join(' · ');
    void open() =>
        TodoDetailRoute(listId: todo.listId, todoId: todo.id).go(context);
    final row = Row(
      children: [
        SizedBox.square(
          dimension: HiwiskiMetrics.minTapTarget,
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: l.todoDone,
            icon: Icon(
              HiwiskiSymbols.checkBoxOutlineBlank,
              size: HiwiskiMetrics.icon26,
              color: scheme.onSurfaceVariant,
            ),
            onPressed: () => ref
                .read(calendarOverviewViewModelProvider.notifier)
                .completeTask(todo),
          ),
        ),
        const SizedBox(width: HiwiskiMetrics.space8),
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            mainAxisSize: .min,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: todo.title),
                    if (todo.entityKey case final key?)
                      TextSpan(
                        text: '  $key',
                        style: context.tokens.text.entityKey,
                      ),
                  ],
                ),
                maxLines: 2,
                overflow: .ellipsis,
                style: context.texts.bodyLarge?.copyWith(fontWeight: .w500),
              ),
              Padding(
                padding: const .only(top: HiwiskiMetrics.space4),
                child: Text(
                  meta,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: context.texts.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!framed) const RowChevron(),
      ],
    );
    if (framed) {
      const shape = RoundedRectangleBorder(
        borderRadius: .all(.circular(HiwiskiMetrics.radiusMenu)),
      );
      return Material(
        key: CalendarKeys.dueTask(todo.id),
        color: scheme.surface,
        shape: shape.copyWith(side: BorderSide(color: scheme.outlineVariant)),
        child: InkWell(
          customBorder: shape,
          onTap: open,
          child: Padding(
            padding: const .only(right: HiwiskiMetrics.space12),
            child: row,
          ),
        ),
      );
    }
    return Column(
      key: CalendarKeys.dueTask(todo.id),
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: [
        InkWell(
          onTap: open,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: HiwiskiMetrics.listRowHeightTall,
            ),
            child: Padding(
              padding: const .symmetric(vertical: HiwiskiMetrics.space6),
              child: row,
            ),
          ),
        ),
        const RowDivider(),
      ],
    );
  }
}
