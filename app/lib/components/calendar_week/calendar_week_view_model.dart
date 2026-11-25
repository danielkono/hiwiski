import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/repositories.dart';
import '../../domain/calendar/calendar_items.dart';
import '../../domain/calendar/occurrence.dart';
import '../../domain/common/calendar_days.dart';
import '../../domain/wiki/mindmap.dart' show calendarIdsOf;

part 'calendar_week_view_model.g.dart';

@riverpod
Stream<List<Calendar>> _calendars(Ref ref) =>
    ref.watch(calendarRepositoryProvider).watchCalendars();

@riverpod
Stream<List<CalendarEvent>> _events(Ref ref) =>
    ref.watch(calendarRepositoryProvider).watchEvents();

/// A week of some calendars, side by side — as a mind map shows one.
@immutable
class const CalendarWeekState({
  /// The calendars chosen that this member can see, by id: one they cannot see is
  /// not on this device, and its events show nowhere — here neither.
  required final Map<String, Calendar> calendars,

  /// Their events in the week, a series by each of its days in it, in order.
  required final List<Occurrence> occurrences,

  /// Monday to Sunday.
  required final List<DateTime> days,
});

@riverpod
class CalendarWeekViewModel extends _$CalendarWeekViewModel {
  /// The week from [monday] of the calendars [calendars] names — their ids separated
  /// by spaces, as a mind map keeps them: a list would be another provider with
  /// every build.
  @override
  Future<CalendarWeekState> build(String calendars, DateTime monday) async {
    final calendarSource = ref.watch(_calendarsProvider.future);
    final eventSource = ref.watch(_eventsProvider.future);
    final chosen = calendarIdsOf(calendars).toSet();
    final from = startOfDay(monday);
    final to = addDays(from, DateTime.daysPerWeek);
    const expander = EventExpander();
    final shown = {
      for (final calendar in await calendarSource)
        if (chosen.contains(calendar.id)) calendar.id: calendar,
    };
    return CalendarWeekState(
      calendars: shown,
      occurrences: <Occurrence>[
        for (final event in await eventSource)
          if (shown.containsKey(event.calendarId))
            ...expander.expand(event, from, to),
      ]..sort(),
      days: [
        for (int day = 0; day < DateTime.daysPerWeek; day++) addDays(from, day),
      ],
    );
  }
}
