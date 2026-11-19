import 'dart:collection';

import '../common/calendar_days.dart';
import 'occurrence.dart';

/// The lane of every multi-day event within one row of days — a week of the month grid,
/// or the band above the week view's hours.
///
/// Each cell used to stack its spans from the top in its own order. When a second span
/// began in the middle of a first one, the first moved down a row from that day on, and
/// its line broke — nobody could tell any more where it began or ended. A span keeps its
/// lane across the row, and a free lane stays a gap.
///
/// Per row and not for the whole grid: lanes taken in other weeks pushed a week's
/// spans down until they no longer fit and were left out. Spans are clipped to
/// [from]–[to] (inclusive days) when given, so one that ended last week does not block
/// a lane in this one.
///
/// Greedy, like every calendar: by first day (longer first on a tie), each into the
/// lowest lane that is free again.
Map<Occurrence, int> assignSpanLanes(
  Iterable<Occurrence> spans, {
  DateTime? from,
  DateTime? to,
}) {
  DateTime firstOf(Occurrence span) {
    final first = startOfDay(span.start);
    return from != null && first.isBefore(from) ? startOfDay(from) : first;
  }

  DateTime lastOf(Occurrence span) {
    final last = startOfDay(span.end);
    return to != null && last.isAfter(to) ? startOfDay(to) : last;
  }

  final sorted =
      spans
          .where(
            (span) =>
                (to == null || !firstOf(span).isAfter(to)) &&
                (from == null || !lastOf(span).isBefore(from)),
          )
          .toList()
        ..sort((a, b) {
          final byStart = firstOf(a).compareTo(firstOf(b));
          if (byStart != 0) return byStart;
          return lastOf(b).compareTo(lastOf(a));
        });

  final lanes = LinkedHashMap<Occurrence, int>.identity();
  final lastDayOfLane = <DateTime>[];
  for (final span in sorted) {
    final first = firstOf(span);
    int lane = lastDayOfLane.indexWhere((last) => last.isBefore(first));
    if (lane < 0) {
      lane = lastDayOfLane.length;
      lastDayOfLane.add(lastOf(span));
    } else {
      lastDayOfLane[lane] = lastOf(span);
    }
    lanes[span] = lane;
  }
  return lanes;
}
