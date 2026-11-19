import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/common/wire.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/color_tokens.dart';
import '../../../../domain/calendar/calendar_items.dart';
import '../../../../domain/calendar/occurrence.dart';
import '../../../../domain/calendar/span_lanes.dart';
import '../../../../domain/common/calendar_days.dart';
import '../../view/event_tile.dart';
import '../calendar_overview_view_model.dart';
import 'due_task_tile.dart';
import 'pinned_strip.dart';

/// The month view.
///
/// "Below it up to **three dots** in the color of the respective calendar. At the bottom
/// edge of the cell a **continuous bar** for multi-day events. **Dots for single
/// events, bars for spans — both, because each means something different.**"
class MonthGrid extends ConsumerWidget {
  const MonthGrid({
    super.key,
    required this.state,
    required this.occurrences,
    required this.calendars,
    required this.padding,
    this.pinnedStrip = true,
  });

  /// The calendar's state: the selected day, the strip's content.
  final CalendarOverviewState state;
  final List<Occurrence> occurrences;
  final Map<String, Calendar> calendars;
  final EdgeInsets padding;

  /// The selected day's all-day events in a strip below the grid, and not again in
  /// its card.
  final bool pinnedStrip;

  /// "Cells 52 high." — a week with more spans than two grows by a line per span.
  static const cellHeight = HiwiskiMetrics.monthCellHeight;

  /// One span line: the bar and the gap above it — for an occupied lane and an empty
  /// one alike. The empty one was a pixel shorter, and a lower lane's bar stepped up
  /// in the cells where the lane above it was free.
  static const laneHeight = HiwiskiMetrics.hairline + HiwiskiMetrics.barHeight;

  /// "Number in a 32 circle."
  static const dayCircle = HiwiskiMetrics.dayCircle;

  static const maxDots = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final locale = Localizations.localeOf(context).toString();
    final view = state;

    final first = DateTime(view.selectedDay.year, view.selectedDay.month);
    final gridStart = startOfWeek(first);
    final today = startOfDay(clock.now());

    final pinnedOfDay = view.pinnedOfSelectedDay;
    final cardItems = view.cardsOfSelectedDay;
    final spans = occurrences.where((item) => item.isMultiDay).toList();
    final sorted = [...occurrences]..sort();
    final byDay = occurrencesByDay(sorted, gridStart, addDays(gridStart, 41));

    return ListView(
      padding: padding.add(const .only(bottom: HiwiskiMetrics.fabClearance)),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                DateFormat.yMMMM(locale).format(first),
                style: context.texts.titleMedium,
              ),
            ),
            // Back to today in one tap — only offered where today is out of sight.
            if (first.year != today.year || first.month != today.month)
              TextButton(
                onPressed: () => ref
                    .read(calendarOverviewViewModelProvider.notifier)
                    .selectDay(today),
                child: Text(l.calToday),
              ),
            IconButton(
              icon: const Icon(HiwiskiSymbols.chevronLeft),
              tooltip: MaterialLocalizations.of(context).previousMonthTooltip,
              onPressed: () => ref
                  .read(calendarOverviewViewModelProvider.notifier)
                  .shiftMonth(-1),
            ),
            IconButton(
              icon: const Icon(HiwiskiSymbols.chevronRight),
              tooltip: MaterialLocalizations.of(context).nextMonthTooltip,
              onPressed: () => ref
                  .read(calendarOverviewViewModelProvider.notifier)
                  .shiftMonth(1),
            ),
          ],
        ),
        _WeekdayRow(locale: locale),
        // 6×7 grid. Lanes per week: a span keeps its line across the row, and every
        // span gets one — the row grows instead of leaving a third span out.
        for (var week = 0; week < 6; week++)
          Builder(
            builder: (context) {
              final monday = addDays(gridStart, week * 7);
              final lanes = assignSpanLanes(
                spans,
                from: monday,
                to: addDays(monday, 6),
              );
              final laneCount = lanes.values.fold<int>(
                0,
                (most, lane) => lane + 1 > most ? lane + 1 : most,
              );
              return Row(
                children: [
                  for (var weekday = 0; weekday < 7; weekday++)
                    Expanded(
                      child: _Cell(
                        day: addDays(monday, weekday),
                        month: first.month,
                        today: today,
                        selected: startOfDay(view.selectedDay),
                        touching:
                            byDay[dayKeyOf(addDays(monday, weekday))] ??
                            const [],
                        lanes: lanes,
                        laneCount: laneCount,
                        hasTasks:
                            view.tasks[addDays(monday, weekday)]?.isNotEmpty ??
                            false,
                        calendars: calendars,
                        onTap: (day) => ref
                            .read(calendarOverviewViewModelProvider.notifier)
                            .selectDay(day),
                      ),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: HiwiskiMetrics.space16),
        // The selected day's all-day events, once with from–to — below the grid, where
        // the eye is after tapping a day.
        if (pinnedOfDay.isNotEmpty)
          PinnedStrip(
            occurrences: pinnedOfDay,
            calendars: calendars,
            padding: .zero,
          ),
        // "Below it a card with the events of the selected day." The same tiles as
        // in the list, so an event looks alike in both views.
        Card(
          child: Padding(
            padding: const .all(HiwiskiMetrics.space14),
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                Text(
                  DateFormat.MMMMEEEEd(locale).format(view.selectedDay),
                  style: context.texts.titleSmall?.copyWith(
                    color: startOfDay(view.selectedDay) == today
                        ? context.scheme.primary
                        : null,
                  ),
                ),
                const SizedBox(height: HiwiskiMetrics.space10),
                for (final task in view.tasksOfSelectedDay)
                  DueTaskTile(task: task),
                if (cardItems.isEmpty && view.tasksOfSelectedDay.isEmpty)
                  Text(
                    l.calNothingPlannedCard,
                    style: context.texts.bodyMedium?.copyWith(
                      color: context.scheme.onSurfaceVariant,
                    ),
                  )
                else
                  for (final occurrence in cardItems)
                    EventTile(
                      occurrence: occurrence,
                      calendar: calendars[occurrence.event.calendarId],
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow({required this.locale});

  final String locale;

  @override
  Widget build(BuildContext context) {
    final symbols = DateFormat.EEEE(locale).dateSymbols;
    return Padding(
      padding: const .symmetric(vertical: HiwiskiMetrics.space6),
      child: Row(
        children: [
          // Mon–Sun, not Sun–Sat: the design shows the week the European way.
          for (var day = DateTime.monday; day <= DateTime.sunday; day++)
            Expanded(
              child: Text(
                symbols.NARROWWEEKDAYS[day % 7],
                textAlign: .center,
                style: context.texts.labelSmall?.copyWith(
                  fontWeight: .w600,
                  // The weekend stands out a little: that is where family plans pile up.
                  color: day >= DateTime.saturday
                      ? context.scheme.primary
                      : context.scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.day,
    required this.month,
    required this.today,
    required this.selected,
    required this.touching,
    required this.lanes,
    required this.laneCount,
    required this.calendars,
    required this.onTap,
    this.hasTasks = false,
  });

  /// A task is due that day: a small box next to the dots, not a dot of its own
  /// color — a task belongs to no calendar.
  final bool hasTasks;

  final DateTime day;
  final int month;
  final DateTime today;
  final DateTime selected;

  /// What touches this day, in order.
  final List<Occurrence> touching;

  /// The lane of every span, the same in every cell of the week.
  final Map<Occurrence, int> lanes;

  /// Lanes the week uses — every cell of it is as tall as they need.
  final int laneCount;
  final Map<String, Calendar> calendars;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isToday = day == today;
    final isSelected = day == selected;
    final inMonth = day.month == month;

    final dots = touching
        .where((item) => !item.isMultiDay)
        .take(MonthGrid.maxDots);
    // Per lane: the span in it today, or none — a gap keeps the lines below in place.
    final byLane = <int, Occurrence>{
      for (final item in touching.where((item) => item.isMultiDay))
        ?lanes[item]: item,
    };

    return InkWell(
      onTap: () => onTap(day),
      customBorder: const RoundedRectangleBorder(
        borderRadius: .all(.circular(HiwiskiMetrics.radiusMenu)),
      ),
      child: SizedBox(
        // Two lines fit the 52; each further one adds its own.
        height:
            MonthGrid.cellHeight +
            (laneCount > 2 ? (laneCount - 2) * MonthGrid.laneHeight : 0),
        child: Column(
          mainAxisAlignment: .center,
          children: [
            Container(
              width: MonthGrid.dayCircle,
              height: MonthGrid.dayCircle,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: .circle,
                // "selected day filled", "today with a 1.5 px ring in `pri`".
                color: isSelected ? context.scheme.primary : null,
                border: isToday && !isSelected
                    ? Border.fromBorderSide(
                        BorderSide(
                          color: context.scheme.primary,
                          width: HiwiskiMetrics.strokeBold,
                        ),
                      )
                    : null,
              ),
              child: Text(
                '${day.day}',
                style: context.texts.bodyMedium?.copyWith(
                  color: switch ((isSelected, inMonth)) {
                    (true, _) => context.scheme.onPrimary,
                    (false, true) => context.scheme.onSurface,
                    (false, false) =>
                      context.scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  },
                ),
              ),
            ),
            SizedBox(
              height: HiwiskiMetrics.dotTiny,
              child: Row(
                mainAxisAlignment: .center,
                children: [
                  if (hasTasks)
                    Container(
                      margin: const .symmetric(
                        horizontal: HiwiskiMetrics.hairline,
                      ),
                      width: HiwiskiMetrics.dotTiny,
                      height: HiwiskiMetrics.dotTiny,
                      decoration: BoxDecoration(
                        border: .fromBorderSide(
                          BorderSide(
                            color: context.scheme.primary,
                            width: HiwiskiMetrics.hairline,
                          ),
                        ),
                      ),
                    ),
                  for (final occurrence in dots)
                    Container(
                      margin: const .symmetric(
                        horizontal: HiwiskiMetrics.hairline,
                      ),
                      width: HiwiskiMetrics.dotTiny,
                      height: HiwiskiMetrics.dotTiny,
                      decoration: BoxDecoration(
                        shape: .circle,
                        color: tokens.accent(
                          accentOf(
                            calendars[occurrence.event.calendarId]
                                    ?.colorToken ??
                                ColorTokens.blue,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // The continuous bar at the bottom edge: it runs from cell edge to cell edge
            // so that a span across the week reads as one line and not as seven
            // dashes. On its first and last day it is inset and rounded — that is where
            // it begins and ends.
            for (var lane = 0; lane < laneCount; lane++)
              if (byLane[lane] case final occurrence?)
                Container(
                  height: HiwiskiMetrics.barHeight,
                  margin: .only(
                    top: HiwiskiMetrics.hairline,
                    left: occurrence.day == day ? HiwiskiMetrics.space4 : 0,
                    right: startOfDay(occurrence.end) == day
                        ? HiwiskiMetrics.space4
                        : 0,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.accent(
                      accentOf(
                        calendars[occurrence.event.calendarId]?.colorToken ??
                            ColorTokens.blue,
                      ),
                    ),
                    borderRadius: .horizontal(
                      left: .circular(
                        occurrence.day == day ? HiwiskiMetrics.radiusBar : 0,
                      ),
                      right: .circular(
                        startOfDay(occurrence.end) == day
                            ? HiwiskiMetrics.radiusBar
                            : 0,
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(height: MonthGrid.laneHeight),
          ],
        ),
      ),
    );
  }
}
