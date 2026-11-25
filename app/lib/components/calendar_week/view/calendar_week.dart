import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/common/wire.dart';
import '../../../core/routing/item_navigation.dart';
import '../../../core/ui/notice_bar.dart';
import '../../../core/ui/week_timeline.dart';
import '../calendar_week_view_model.dart';

/// A week of some calendars, side by side, read only: as the calendar's week view
/// shows it, an event opening into its card when the pointer rests on it — or, on a
/// touch screen, when it is held — with what the calendar's own card shows.
///
/// A calendar the member cannot see shows nothing: its events are not on this device.
class CalendarWeek extends ConsumerWidget {
  const CalendarWeek({
    super.key,
    required this.calendars,
    required this.monday,
  });

  /// The calendars' ids, separated by spaces.
  final String calendars;

  /// The week's first day.
  final DateTime monday;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(calendarWeekViewModelProvider(calendars, monday))
      .when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (error, _) => NoticeBar.failure(context, error: error),
        data: (week) => LayoutBuilder(
          builder: (context, constraints) {
            final timeline = WeekTimeline(
              days: week.days,
              occurrences: week.occurrences,
              calendars: week.calendars,
              height: constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : null,
              preview: (context, occurrence) => ItemPreview(
                itemType: EntityTypes.event,
                itemId: occurrence.event.id,
                at: occurrence.start,
              ),
            );
            if (!constraints.hasBoundedHeight) return timeline;
            // Fitted into the height as far as its hours stay readable; a busy week
            // in a low box is cut at the bottom rather than squeezed.
            return ClipRect(
              child: OverflowBox(
                alignment: .topCenter,
                maxHeight: .infinity,
                child: timeline,
              ),
            );
          },
        ),
      );
}
