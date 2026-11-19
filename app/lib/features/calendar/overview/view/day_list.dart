import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/common/date_patterns.dart';
import '../../../../core/common/wire.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/item_navigation.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/color_tokens.dart';
import '../../../../domain/calendar/due_task.dart';
import '../../../../domain/calendar/calendar_items.dart';
import '../../../../domain/calendar/occurrence.dart';
import '../../../../domain/common/calendar_days.dart';
import '../../view/calendar_keys.dart';
import '../../view/date_badge.dart';
import '../../view/event_tile.dart';
import 'due_task_tile.dart';
import 'pinned_strip.dart' show spanRange;

/// The list view: grouped by day.
///
/// Each day is a group with the date on the left (today filled in `pri`) and its
/// events as tinted tiles on the right. **Days without events stay visible**, so the
/// rhythm of the week does — but quietly, and runs of them are collapsed ("Wed – Thu,
/// 30.09.–01.10."). The same goes for days that only an all-day span covers: twelve
/// headers saying "Autumn break" become one line with the span.
class DayList extends ConsumerWidget {
  const DayList({
    super.key,
    required this.occurrences,
    required this.pinned,
    required this.calendars,
    required this.padding,
    required this.from,
    required this.to,
    this.tasks = const {},
  });

  /// The tasks due, by day — a day with one is not quiet.
  final Map<DateTime, List<DueTask>> tasks;

  final List<Occurrence> occurrences;

  /// All-day events sit in the strip and not again as tiles — but a day that has an
  /// all-day event on it is not empty.
  final List<Occurrence> pinned;

  final Map<String, Calendar> calendars;
  final EdgeInsets padding;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = _build(context);

    return ListView.builder(
      padding: padding.add(
        const .only(
          top: HiwiskiMetrics.space8,
          bottom: HiwiskiMetrics.fabClearance,
        ),
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) => entries[index],
    );
  }

  List<Widget> _build(BuildContext context) {
    final l = L.of(context);
    final locale = Localizations.localeOf(context).toString();
    final today = startOfDay(clock.now());

    final byDay = <DateTime, List<Occurrence>>{};
    for (final occurrence in occurrences) {
      byDay.putIfAbsent(startOfDay(occurrence.start), () => []).add(occurrence);
    }

    final widgets = <Widget>[];
    final shortDay = DateFormat.E(locale);
    final date = DateFormat(DatePatterns.dayMonth, locale);
    final month = DateFormat.yMMMM(locale);
    DateTime? lastMonth;

    // A month label where the month changes — after a long quiet stretch it says
    // where one is.
    void monthLabel(DateTime day) {
      final key = DateTime(day.year, day.month);
      if (lastMonth != null && lastMonth != key) {
        widgets.add(_MonthLabel(month.format(day)));
      }
      lastMonth = key;
    }

    // A run: consecutive days without events of their own and the same spans over
    // them — none, or e.g. "Autumn break". Today is never part of a run.
    List<DateTime> run = <DateTime>[];
    List<Occurrence> runSpans = <Occurrence>[];

    void flushRun() {
      if (run.isEmpty) return;
      final first = run.first;
      final last = run.last;
      monthLabel(first);
      final String when;
      if (run.length == 1) {
        when =
            '${DateFormat.EEEE(locale).format(first)}, ${date.format(first)}';
      } else if (run.length <= 7) {
        // Across more than a week "Wed – Thu" means nothing any more; then only the
        // dates show.
        when =
            '${shortDay.format(first)} – ${shortDay.format(last)}, '
            '${date.format(first)}–${date.format(last)}';
      } else {
        when = '${date.format(first)}–${date.format(last)}';
      }
      widgets.add(
        _QuietDays(
          when: when,
          label: runSpans.isEmpty ? l.calNothingPlanned : null,
          spans: runSpans,
          calendars: calendars,
        ),
      );
      run = [];
      runSpans = [];
    }

    for (final day in daysBetween(from, to)) {
      final items = byDay[day] ?? const <Occurrence>[];
      final spans = pinned.where((item) => item.touches(day)).toList();
      final dayTasks = tasks[day] ?? const <DueTask>[];
      final isToday = day == today;

      if (items.isEmpty && dayTasks.isEmpty && !isToday) {
        final sameSpans =
            spans.length == runSpans.length &&
            spans.every((item) => runSpans.contains(item));
        if (run.isNotEmpty && !sameSpans) flushRun();
        if (run.isEmpty) runSpans = spans;
        run.add(day);
        continue;
      }

      flushRun();
      monthLabel(day);
      widgets.add(
        _DayGroup(
          day: day,
          isToday: isToday,
          label: switch (day) {
            _ when isToday => l.calToday,
            _ when day == addDays(today, 1) => l.calTomorrow,
            _ => null,
          },
          occurrences: items,
          spans: spans,
          tasks: dayTasks,
          calendars: calendars,
        ),
      );
    }
    flushRun();
    return widgets;
  }
}

/// One day with something on it — or today, which always shows.
class _DayGroup extends StatelessWidget {
  const _DayGroup({
    required this.day,
    required this.isToday,
    required this.label,
    required this.occurrences,
    required this.spans,
    required this.calendars,
    this.tasks = const [],
  });

  /// Due that day — above the events, as a task is a whole day's matter.
  final List<DueTask> tasks;

  final DateTime day;
  final bool isToday;

  /// "Today" or "Tomorrow" above the tiles; other days only carry the badge.
  final String? label;
  final List<Occurrence> occurrences;
  final List<Occurrence> spans;
  final Map<String, Calendar> calendars;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final locale = Localizations.localeOf(context).toString();
    final empty = occurrences.isEmpty && tasks.isEmpty;

    return Padding(
      padding: const .only(bottom: HiwiskiMetrics.space16),
      child: Row(
        crossAxisAlignment: .start,
        spacing: HiwiskiMetrics.space8,
        children: [
          DateBadge(day: day, isToday: isToday, muted: empty),
          Expanded(
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                // "Today" and "Tomorrow" say so; any other day has its badge.
                if (label != null)
                  Padding(
                    padding: const .only(
                      top: HiwiskiMetrics.space2,
                      bottom: HiwiskiMetrics.space6,
                    ),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (label != null)
                            TextSpan(
                              text: '$label  ',
                              style: TextStyle(
                                fontWeight: .w700,
                                color: isToday
                                    ? context.scheme.primary
                                    : context.scheme.onSurface,
                              ),
                            ),
                          TextSpan(
                            text: DateFormat.MMMMd(locale).format(day),
                            style: TextStyle(
                              color: context.scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      style: context.texts.bodyMedium,
                    ),
                  ),
                if (spans.isNotEmpty)
                  Padding(
                    padding: const .only(bottom: HiwiskiMetrics.space6),
                    child: _SpanChips(spans: spans, calendars: calendars),
                  ),
                if (empty && spans.isEmpty)
                  Text(
                    l.calNothingPlanned,
                    style: context.texts.bodyMedium?.copyWith(
                      color: context.scheme.onSurfaceVariant,
                    ),
                  ),
                // Rows parted by their own lines, as in a task list.
                for (final task in tasks) DueTaskTile(task: task),
                for (final occurrence in occurrences)
                  EventTile(
                    occurrence: occurrence,
                    calendar: calendars[occurrence.event.calendarId],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Days with nothing of their own: one quiet line for the whole run.
class _QuietDays extends StatelessWidget {
  const _QuietDays({
    required this.when,
    required this.label,
    required this.spans,
    required this.calendars,
  });

  final String when;

  /// "nothing planned" — or `null` when spans fill the days.
  final String? label;
  final List<Occurrence> spans;
  final Map<String, Calendar> calendars;

  @override
  Widget build(BuildContext context) {
    final muted = context.texts.bodyMedium?.copyWith(
      color: context.scheme.onSurfaceVariant,
    );
    return Padding(
      padding: const .only(bottom: HiwiskiMetrics.space16),
      child: Row(
        crossAxisAlignment: .start,
        children: [
          // The badge column stays empty, so the line sits under the dates' tiles
          // and the run reads as a gap in the rhythm, not as a day of its own.
          const SizedBox(width: DateBadge.width + HiwiskiMetrics.space8),
          Expanded(
            child: Container(
              padding: const .symmetric(
                horizontal: HiwiskiMetrics.space12,
                vertical: HiwiskiMetrics.space8,
              ),
              decoration: BoxDecoration(
                borderRadius: const .all(.circular(HiwiskiMetrics.radiusMenu)),
                border: .fromBorderSide(
                  BorderSide(color: context.tokens.divider),
                ),
              ),
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(label == null ? when : '$when · $label', style: muted),
                  if (spans.isNotEmpty) ...[
                    const SizedBox(height: HiwiskiMetrics.space6),
                    _SpanChips(spans: spans, calendars: calendars),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The spans over a day, as small pills in their calendar's tint: the name, and for one
/// over several days its "from–to" — the strip at the top may be switched off.
class _SpanChips extends StatelessWidget {
  const _SpanChips({required this.spans, required this.calendars});

  final List<Occurrence> spans;
  final Map<String, Calendar> calendars;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: HiwiskiMetrics.space6,
    runSpacing: HiwiskiMetrics.space6,
    children: [
      for (final span in spans)
        Builder(
          builder: (context) {
            final tint =
                context.tokens.tags[tintOf(
                  calendars[span.event.calendarId]?.colorToken ??
                      ColorTokens.blue,
                )]!;
            // A pill opens its event like any tile — it used to be a mere label.
            return Material(
              color: tint.background,
              borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
              child: InkWell(
                key: CalendarKeys.spanChip(span.event.id),
                borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
                onTap: () => openOccurrence(context, span),
                child: Padding(
                  padding: const .symmetric(
                    horizontal: HiwiskiMetrics.space10,
                    vertical: HiwiskiMetrics.space4,
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: span.event.title),
                        if (span.isMultiDay)
                          TextSpan(
                            text:
                                '  ${spanRange(span, Localizations.localeOf(context).toString())}',
                            style: context.texts.bodySmall?.copyWith(
                              color: tint.foreground,
                            ),
                          ),
                      ],
                    ),
                    overflow: .ellipsis,
                    style: context.texts.labelLarge?.copyWith(
                      color: tint.foreground,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
    ],
  );
}

/// "November 2026" where the month changes.
class _MonthLabel extends StatelessWidget {
  const _MonthLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .only(
      top: HiwiskiMetrics.space8,
      bottom: HiwiskiMetrics.space12,
    ),
    child: Text(text, style: context.tokens.text.sectionLabel),
  );
}
