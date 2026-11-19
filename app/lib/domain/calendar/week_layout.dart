import '../common/calendar_days.dart';
import 'occurrence.dart';

/// One timed occurrence on its day in the week view, in minutes from midnight — and
/// where it sits beside the ones it overlaps.
class DayPiece {
  DayPiece({
    required this.occurrence,
    required this.day,
    required this.start,
    required this.end,
  });

  final Occurrence occurrence;

  /// The column of the day, 0 for the first day shown.
  final int day;

  /// Minutes from midnight. [end] is at least [WeekLayout.minLength] after [start], so
  /// a reminder at 8:00 without an end still gets a block to tap.
  final int start;
  final int end;

  /// Side by side with the ones it overlaps: its place, and how many share the width.
  int column = 0;
  int columns = 1;
}

/// A stretch of the day that is shown — between two of them the view skips.
class TimeSegment {
  const TimeSegment(this.start, this.end);

  /// Minutes from midnight, on full hours.
  final int start;
  final int end;

  int get length => end - start;

  @override
  bool operator ==(Object other) =>
      other is TimeSegment && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TimeSegment($start–$end)';
}

/// How the week view lays out its timed events.
///
/// **Only the hours that hold something are shown.** The empty morning and evening are
/// cut off, and a long empty stretch in between is skipped — the view marks the skip —
/// so a whole week fits at once and one sees how a day's events stand to each other.
/// Short gaps stay: a free hour between two events is part of the picture.
class WeekLayout {
  WeekLayout._(this.days, this.segments, this.pieces);

  /// The shortest block, in minutes.
  static const minLength = 30;

  /// An empty stretch at least this long between two busy ones is skipped.
  static const minGap = 90;

  final List<DateTime> days;

  /// The shown stretches, in order; empty when no day has a timed event.
  final List<TimeSegment> segments;

  /// Per day, its pieces by start.
  final List<List<DayPiece>> pieces;

  int get shownMinutes =>
      segments.fold(0, (total, segment) => total + segment.length);

  /// [occurrences] may hold anything; only timed ones within a single day are laid out
  /// here — all-day and multi-day ones belong in the band above the hours.
  ///
  /// [always] is shown even where nothing is: the calendar's week, where a tap into
  /// the hours creates an event and a drop moves one, needs hours to tap and drop on
  /// — on an empty week too.
  factory WeekLayout.of(
    List<DateTime> days,
    Iterable<Occurrence> occurrences, {
    TimeSegment? always,
  }) {
    final pieces = [for (final _ in days) <DayPiece>[]];
    for (final occurrence in occurrences) {
      if (occurrence.isPinned) continue;
      // By the date, not by a difference in days: that rounds across a clock change.
      final day = days.indexWhere(
        (candidate) => startOfDay(candidate) == startOfDay(occurrence.start),
      );
      if (day < 0) continue;
      final start = occurrence.start.hour * 60 + occurrence.start.minute;
      final end = occurrence.end.hour * 60 + occurrence.end.minute;
      pieces[day].add(
        DayPiece(
          occurrence: occurrence,
          day: day,
          start: start,
          end: (end < start + minLength ? start + minLength : end).clamp(
            0,
            24 * 60,
          ),
        ),
      );
    }
    for (final day in pieces) {
      day.sort((a, b) {
        final byStart = a.start.compareTo(b.start);
        return byStart != 0 ? byStart : b.end.compareTo(a.end);
      });
      _arrange(day);
    }
    return WeekLayout._(
      days,
      _segments(pieces.expand((day) => day), always),
      pieces,
    );
  }

  /// The busy stretches of all days together, widened to full hours; neighbours closer
  /// than [minGap] become one.
  static List<TimeSegment> _segments(
    Iterable<DayPiece> pieces,
    TimeSegment? always,
  ) {
    final busy = [
      for (final piece in pieces)
        (
          piece.start ~/ 60 * 60,
          ((piece.end + 59) ~/ 60 * 60).clamp(0, 24 * 60),
        ),
      if (always != null) (always.start, always.end),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final segments = <TimeSegment>[];
    for (final (start, end) in busy) {
      final last = segments.isEmpty ? null : segments.last;
      if (last != null && start - last.end < minGap) {
        if (end > last.end) {
          segments[segments.length - 1] = TimeSegment(last.start, end);
        }
      } else {
        segments.add(TimeSegment(start, end));
      }
    }
    return segments;
  }

  /// Overlapping pieces share the day's width: each cluster of overlaps gets as many
  /// columns as it needs at its fullest, every piece the first one free.
  static void _arrange(List<DayPiece> day) {
    List<DayPiece> cluster = <DayPiece>[];
    int clusterEnd = -1;
    final columnEnds = <int>[];

    void close() {
      for (final piece in cluster) {
        piece.columns = columnEnds.length;
      }
      cluster = [];
      columnEnds.clear();
    }

    for (final piece in day) {
      if (piece.start >= clusterEnd) {
        close();
        clusterEnd = piece.end;
      } else if (piece.end > clusterEnd) {
        clusterEnd = piece.end;
      }
      int column = columnEnds.indexWhere((end) => end <= piece.start);
      if (column < 0) {
        column = columnEnds.length;
        columnEnds.add(piece.end);
      } else {
        columnEnds[column] = piece.end;
      }
      piece.column = column;
      cluster.add(piece);
    }
    close();
  }
}
