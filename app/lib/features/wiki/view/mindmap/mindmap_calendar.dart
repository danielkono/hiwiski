import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../components/calendar_week/view/calendar_week.dart';
import '../../../../core/common/date_patterns.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../domain/common/calendar_days.dart';
import '../../../../domain/wiki/mindmap.dart';

/// A week of calendars on a mind map: which week above, its days side by side below,
/// read only — on the canvas, on the page's preview and in the map saved as a
/// picture alike. Where the map is read, an event opens into its card when the
/// pointer rests on it, or when it is held on a touch screen.
///
/// Without a week of its own it shows the current one, and moves on at midnight
/// while it is shown. Its text size makes the whole week larger, as a link's content
/// grows ([textScale]): the week brings its own text styles.
class MindmapCalendar extends StatefulWidget {
  const MindmapCalendar({
    super.key,
    required this.node,
    required this.textScale,
  });

  final MindmapNode node;
  final double textScale;

  /// [monday]'s week as a heading names it: "Week 28 · 12.07.–18.07.2027".
  static String weekLabelOf(BuildContext context, DateTime monday) {
    final locale = Localizations.localeOf(context).toString();
    final sunday = addDays(monday, DateTime.daysPerWeek - 1);
    final range =
        '${DateFormat(DatePatterns.dayMonth, locale).format(monday)}'
        '$_dash'
        '${DateFormat(DatePatterns.dayMonthYear, locale).format(sunday)}';
    return L.of(context).mindmapWeekOf(isoWeekNumber(monday), range);
  }

  static const _dash = '–';

  @override
  State<MindmapCalendar> createState() => _MindmapCalendarState();
}

class _MindmapCalendarState extends State<MindmapCalendar> {
  DateTime _today = startOfDay(clock.now());
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(MindmapCalendar old) {
    super.didUpdateWidget(old);
    if (old.node.week != widget.node.week) _schedule();
  }

  @override
  void dispose() {
    _midnight?.cancel();
    super.dispose();
  }

  /// The current week moves on at midnight, even while the map stays open.
  void _schedule() {
    _midnight?.cancel();
    if (widget.node.week != null) return;
    final now = clock.now();
    _midnight = Timer(addDays(startOfDay(now), 1).difference(now), () {
      if (!mounted) return;
      setState(() => _today = startOfDay(clock.now()));
      _schedule();
    });
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final l = L.of(context);
    final ink = DefaultTextStyle.of(context).style.color;
    if (node.calendarIds.isEmpty) {
      return Center(
        child: Text(l.mindmapCalendarNone, textAlign: .center, overflow: .fade),
      );
    }
    final monday = node.weekStart(_today);
    final content = MediaQuery(
      // The scale is the element's own text size, not the device's as well.
      data: MediaQuery.of(context).copyWith(textScaler: .noScaling),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: HiwiskiMetrics.space6,
        children: [
          Row(
            spacing: HiwiskiMetrics.space6,
            children: [
              Icon(
                HiwiskiSymbols.calendarViewWeek,
                size: HiwiskiMetrics.icon18,
                color: ink,
              ),
              Expanded(
                child: Text(
                  MindmapCalendar.weekLabelOf(context, monday),
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: ink),
                ),
              ),
            ],
          ),
          Expanded(
            // On the theme's surface, as in the calendar: its days and hours are
            // written for it, and on an element of a colour of its own they were
            // hard to read. The element's colour frames the week and its heading.
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: .circular(HiwiskiMetrics.radiusChip),
              ),
              child: Padding(
                padding: const .all(HiwiskiMetrics.space4),
                child: CalendarWeek(
                  calendars: node.calendars ?? '',
                  monday: monday,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    final scale = widget.textScale;
    if (scale == 1) return content;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return content;
        }
        // Laid out smaller and drawn larger: text, events and lines grow together.
        return FittedBox(
          fit: .fill,
          alignment: .topLeft,
          clipBehavior: .hardEdge,
          child: SizedBox(
            width: constraints.maxWidth / scale,
            height: constraints.maxHeight / scale,
            child: content,
          ),
        );
      },
    );
  }
}
