import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/common/date_patterns.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/week_timeline.dart';
import '../../../../domain/calendar/due_task.dart';
import '../../../../domain/calendar/calendar_items.dart';
import '../../../../domain/calendar/occurrence.dart';
import '../../../../domain/calendar/reschedule.dart';
import '../../../../domain/calendar/week_layout.dart';
import '../../../../domain/common/calendar_days.dart';
import '../../event/view/event_body.dart';
import '../../event_sheet/view/event_sheet.dart';
import '../../view/series_scope_dialog.dart';
import '../calendar_overview_view_model.dart';
import 'due_task_tile.dart';

/// The week view: the week's navigation above the
/// [WeekTimeline].
class WeekView extends ConsumerWidget {
  /// The hours always shown, in minutes from midnight.
  static const _dayFrom = 8 * 60;
  static const _dayUntil = 20 * 60;

  const WeekView({
    super.key,
    required this.state,
    required this.occurrences,
    required this.calendars,
    required this.padding,
  });

  /// The calendar's state: the selected day, the strip's content.
  final CalendarOverviewState state;
  final List<Occurrence> occurrences;
  final Map<String, Calendar> calendars;
  final EdgeInsets padding;

  /// A dropped event: a series asks how far the move reaches before anything is
  /// written — whoever only sees it afterwards has already moved the
  /// whole series.
  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    Occurrence occurrence,
    WeekSlot slot,
  ) async {
    if (!state.moves(occurrence, slot)) return;
    SeriesScope scope = .wholeSeries;
    if (state.asksScope(occurrence)) {
      final chosen = await askSeriesScope(context, deleting: false);
      if (chosen == null) return;
      scope = chosen;
    }
    await ref
        .read(calendarOverviewViewModelProvider.notifier)
        .moveOccurrence(occurrence, slot, scope: scope);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final locale = Localizations.localeOf(context).toString();
    final view = state;
    final first = startOfWeek(view.selectedDay);
    final days = [for (var i = 0; i < 7; i++) addDays(first, i)];
    final last = addDays(first, 6);
    final today = startOfDay(clock.now());
    final format = DateFormat(DatePatterns.dayMonthName, locale);

    return Padding(
      padding: padding.copyWith(top: 0, bottom: 0),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${l.calWeekNumber(isoWeekNumber(first))}  ',
                        style: const TextStyle(fontWeight: .w600),
                      ),
                      TextSpan(
                        text:
                            '${format.format(first)} – ${format.format(last)}',
                        style: TextStyle(
                          color: context.scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  style: context.texts.titleMedium,
                  overflow: .ellipsis,
                ),
              ),
              // Back to today in one tap — only offered where today is out of sight.
              if (!days.contains(today))
                TextButton(
                  onPressed: () => ref
                      .read(calendarOverviewViewModelProvider.notifier)
                      .selectDay(today),
                  child: Text(l.calToday),
                ),
              IconButton(
                icon: const Icon(HiwiskiSymbols.chevronLeft),
                tooltip: l.calPreviousWeek,
                onPressed: () => ref
                    .read(calendarOverviewViewModelProvider.notifier)
                    .shiftWeek(-1),
              ),
              IconButton(
                icon: const Icon(HiwiskiSymbols.chevronRight),
                tooltip: l.calNextWeek,
                onPressed: () => ref
                    .read(calendarOverviewViewModelProvider.notifier)
                    .shiftWeek(1),
              ),
            ],
          ),
          const SizedBox(height: HiwiskiMetrics.space4),
          // The week's tasks above the hours: due on a day, not at a time.
          if (view.tasksOfWeek case final tasks when tasks.isNotEmpty)
            _WeekTasks(tasks: tasks, locale: locale),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const .only(bottom: HiwiskiMetrics.fabClearance),
                child: WeekTimeline(
                  days: days,
                  occurrences: occurrences,
                  calendars: calendars,
                  // The week at once where the screen allows; scrolled where not.
                  // Measured above the clearance the scroll view adds below it.
                  height: math.max(
                    0,
                    constraints.maxHeight - HiwiskiMetrics.fabClearance,
                  ),
                  selected: startOfDay(view.selectedDay),
                  onDayTap: (day) => ref
                      .read(calendarOverviewViewModelProvider.notifier)
                      .selectDay(day),
                  // Room to tap and drop into, on an empty week too.
                  alwaysShown: const TimeSegment(_dayFrom, _dayUntil),
                  onSlotTap: (slot) =>
                      showEventSheet(context, start: slot.start),
                  canMove: view.movable,
                  onMove: (occurrence, slot) =>
                      _move(context, ref, occurrence, slot),
                  preview: (context, occurrence) =>
                      _EventCard(occurrence: occurrence),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the card an event grows into shows below its title: what the event's
/// preview shows.
class _EventCard extends StatelessWidget {
  const _EventCard({required this.occurrence});

  final Occurrence occurrence;

  @override
  Widget build(BuildContext context) =>
      EventBody(eventId: occurrence.event.id, at: occurrence.start);
}

/// The tasks due this week, each with its weekday — a row that scrolls sideways
/// instead of growing.
class _WeekTasks extends StatelessWidget {
  const _WeekTasks({required this.tasks, required this.locale});

  final List<DueTask> tasks;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final weekday = DateFormat.E(locale);
    return Padding(
      padding: const .only(bottom: HiwiskiMetrics.space8),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: HiwiskiMetrics.space4,
        children: [
          Text(l.calTasksThisWeek, style: context.tokens.text.sectionLabel),
          SingleChildScrollView(
            scrollDirection: .horizontal,
            child: Row(
              spacing: HiwiskiMetrics.space8,
              children: [
                for (final task in tasks)
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: HiwiskiMetrics.treeWidth,
                    ),
                    child: Row(
                      mainAxisSize: .min,
                      spacing: HiwiskiMetrics.space4,
                      children: [
                        Text(
                          weekday.format(task.day),
                          style: context.texts.labelMedium,
                        ),
                        Flexible(child: DueTaskTile(task: task, framed: true)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
