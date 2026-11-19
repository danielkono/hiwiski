import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../app/stores.dart';
import '../../../domain/calendar/calendar_items.dart';
import '../../../domain/calendar/calendar_kinds.dart';
import '../../../domain/calendar/calendar_tags.dart';
import '../../../domain/calendar/due_task.dart';
import '../../../domain/calendar/occurrence.dart';
import '../../../domain/calendar/reschedule.dart';
import '../../../domain/common/calendar_days.dart';
import '../../../domain/tags/tag.dart';
import '../../../domain/todo/todo_items.dart';

part 'calendar_overview_view_model.g.dart';

enum CalendarViewMode { list, week, month }

/// The view as the preferences store it.
const _month = 'MONTH';
const _week = 'WEEK';
const _list = 'LIST';

CalendarViewMode _modeOf(String? stored) => switch (stored) {
  _month => CalendarViewMode.month,
  _week => CalendarViewMode.week,
  _ => CalendarViewMode.list,
};

/// What the calendar shows: the view, the day it stands on, which calendars are hidden
/// and the occurrences of the window the view needs.
@immutable
class CalendarOverviewState {
  const CalendarOverviewState({
    required this.empty,
    required this.calendars,
    required this.mode,
    required this.selectedDay,
    required this.hidden,
    required this.pinnedStrip,
    required this.from,
    required this.to,
    required this.occurrences,
    required this.tags,
    required this.filter,
    this.tasks = const {},
  });

  /// No calendar and no event at all — not "nothing passes the filter".
  final bool empty;

  /// In their order.
  final List<Calendar> calendars;

  final CalendarViewMode mode;
  final DateTime selectedDay;
  final Set<String> hidden;

  /// All-day events in a strip of their own: over the list those of today, below the
  /// month those of the selected day. Off, they stay with their days.
  final bool pinnedStrip;

  /// The window the occurrences are expanded in — the list from today onwards, the
  /// week and the month exactly their block. Otherwise a series without an end would
  /// be expanded to the limit.
  final DateTime from;
  final DateTime to;

  /// In `[from, to)`, in order, through the hidden calendars and the tag filter.
  final List<Occurrence> occurrences;

  final List<Tag> tags;
  final Set<String> filter;

  /// The tasks due in `[from, to)`, by day — on the calendar too, marked as tasks.
  final Map<DateTime, List<DueTask>> tasks;

  /// The tasks of the selected day — below the month.
  List<DueTask> get tasksOfSelectedDay =>
      tasks[startOfDay(selectedDay)] ?? const [];

  /// The tasks of the week shown, in day order.
  List<DueTask> get tasksOfWeek => [
    for (final day in daysBetween(from, to)) ...?tasks[day],
  ];

  Map<String, Calendar> get calendarsById => {
    for (final calendar in calendars) calendar.id: calendar,
  };

  /// Whether a new event has somewhere to go: a calendar that is not subscribed or
  /// imported. Without one, "Event" opened a sheet with no calendar to pick.
  bool get takesEvents =>
      calendars.any((calendar) => !isLockedCalendar(calendar.kind));

  /// Whether the week view lets an event be dragged elsewhere: not one from a
  /// subscribed or imported calendar, which only the source changes.
  bool movable(Occurrence occurrence) =>
      !isLockedCalendar(calendarsById[occurrence.event.calendarId]?.kind);

  /// Whether a drop on [slot] would change [occurrence] at all.
  bool moves(Occurrence occurrence, WeekSlot slot) =>
      movesOccurrence(occurrence, slot);

  /// Whether a drop has to ask how far into the series it reaches.
  bool asksScope(Occurrence occurrence) =>
      occurrence.isSeries && occurrence.originalStart != null;

  List<Occurrence> get pinned =>
      occurrences.where((item) => item.isPinned).toList();

  List<Occurrence> get timed =>
      occurrences.where((item) => !item.isPinned).toList();

  /// Over the list only what touches today: the strip held every holiday of the next
  /// four months and pushed today's events off the screen. The month shows the
  /// selected day's below its grid; the week has its own band.
  List<Occurrence> get pinnedToday {
    if (!pinnedStrip || mode != .list) return const [];
    final today = startOfDay(clock.now());
    return pinned.where((item) => item.touches(today)).toList();
  }

  /// What the selected day holds — below the month, the all-day ones apart in their
  /// strip when it is on.
  List<Occurrence> get _ofSelectedDay =>
      occurrences.where((item) => item.touches(selectedDay)).toList();

  List<Occurrence> get pinnedOfSelectedDay => pinnedStrip
      ? _ofSelectedDay.where((item) => item.isPinned).toList()
      : const [];

  List<Occurrence> get cardsOfSelectedDay => pinnedStrip
      ? _ofSelectedDay.where((item) => !item.isPinned).toList()
      : _ofSelectedDay;
}

@riverpod
Stream<List<Calendar>> _calendars(Ref ref) =>
    ref.watch(calendarRepositoryProvider).watchCalendars();

@riverpod
Stream<List<CalendarEvent>> _events(Ref ref) =>
    ref.watch(calendarRepositoryProvider).watchEvents();

@riverpod
Stream<List<Todo>> _todos(Ref ref) =>
    ref.watch(todoRepositoryProvider).watchAllTodos();

@riverpod
Stream<List<TodoList>> _lists(Ref ref) =>
    ref.watch(todoRepositoryProvider).watchAllLists();

@riverpod
Stream<List<Tag>> _tags(Ref ref) =>
    ref.watch(tagRepositoryProvider).watchTags();

/// The events the calendar shows: not in a hidden calendar, and through the tag filter —
/// a calendar's tags count for its events too (calendar_tags.dart).
///
/// Only what is hidden is left out, not what has no visible calendar: an event shared
/// on its own arrives without its calendar and must still show up, as it does in the
/// calendar widget on the start board.
///
/// A provider and not part of the ViewModel's build: picking a day or turning the
/// month left the events as they were, and still filtered all of them again.
@riverpod
Future<List<CalendarEvent>> _shown(Ref ref) async {
  final hidden = ref.watch(
    preferencesProvider.select((p) => p.hiddenCalendars),
  );
  final filter = ref.watch(
    tagFiltersProvider.select(
      (f) => f[TagFilterAreas.areas] ?? const <String>{},
    ),
  );
  final calendarList = ref.watch(_calendarsProvider.future);
  final events = ref.watch(_eventsProvider.future);
  final calendars = {
    for (final calendar in await calendarList) calendar.id: calendar,
  };
  return [
    for (final event in await events)
      if (!hidden.contains(event.calendarId) &&
          passesTagFilter(
            filter,
            effectiveEventTags(event, calendars[event.calendarId]),
          ))
        event,
  ];
}

/// The occurrences in `[from, to)`, in order — series expanded once per window and not
/// on every build that shows it.
@riverpod
Future<List<Occurrence>> _occurrences(
  Ref ref,
  DateTime from,
  DateTime to,
) async {
  const expander = EventExpander();
  return [
    for (final event in await ref.watch(_shownProvider.future))
      ...expander.expand(event, from, to),
  ]..sort();
}

@riverpod
class CalendarOverviewViewModel extends _$CalendarOverviewViewModel {
  /// Which page holds the filter.
  static const _page = 'calendar';

  static const _area = TagFilterAreas.areas;

  @override
  Future<CalendarOverviewState> build() async {
    ref.watch(tagFilterHoldProvider(_area, _page));
    final mode = ref.watch(
      preferencesProvider.select((p) => _modeOf(p.calendarView)),
    );
    final selected = ref.watch(calendarDayProvider);
    // Whole days, so the same window is the same key for the expansion all day long.
    final today = startOfDay(clock.now());
    final (from, to) = switch (mode) {
      .list => (today, addDays(today, 120)),
      .week => (startOfWeek(selected), addDays(startOfWeek(selected), 7)),
      // The grid shows six full weeks — the window has to cover them, otherwise dots
      // would be missing in the partial weeks at the edges.
      .month => (
        startOfWeek(DateTime(selected.year, selected.month)),
        addDays(startOfWeek(DateTime(selected.year, selected.month)), 42),
      ),
    };
    final hidden = ref.watch(
      preferencesProvider.select((p) => p.hiddenCalendars),
    );
    final pinnedStrip = ref.watch(
      preferencesProvider.select((p) => p.calendarPinnedStrip),
    );
    final tagUses = ref.watch(preferencesProvider.select((p) => p.tagUses));
    final filter = ref.watch(
      tagFiltersProvider.select((f) => f[_area] ?? const <String>{}),
    );
    final calendars = ref.watch(_calendarsProvider.future);
    final events = ref.watch(_eventsProvider.future);
    final occurrences = ref.watch(_occurrencesProvider(from, to).future);
    final tags = ref.watch(_tagsProvider.future);
    final todos = ref.watch(_todosProvider.future);
    final lists = ref.watch(_listsProvider.future);
    final calendarList = await calendars;
    return CalendarOverviewState(
      empty: calendarList.isEmpty && (await events).isEmpty,
      calendars: calendarList,
      mode: mode,
      selectedDay: selected,
      hidden: hidden,
      pinnedStrip: pinnedStrip,
      from: from,
      to: to,
      occurrences: await occurrences,
      tags: rankTags(await tags, tagUses),
      filter: filter,
      tasks: dueTasksByDay(
        await todos,
        await lists,
        from: from,
        to: to,
        filter: filter,
      ),
    );
  }

  /// Ticks a task off right in the calendar — it leaves it then.
  Future<void> completeTask(Todo todo) =>
      ref.read(todoRepositoryProvider).setStatus(todo, true);

  Future<void> setMode(CalendarViewMode mode) =>
      ref.read(preferencesStoreProvider).setCalendarView(switch (mode) {
        .month => _month,
        .week => _week,
        .list => _list,
      });

  void selectDay(DateTime day) =>
      ref.read(calendarDayStoreProvider).select(day);

  /// A week forward or back, on the same weekday.
  void shiftWeek(int weeks) =>
      selectDay(addDays(ref.read(calendarDayProvider), 7 * weeks));

  /// One month forward or back without losing the day of the month.
  ///
  /// `DateTime(2026, 3, 31)` minus one month is 3 March if you compute naively —
  /// so the day is clamped to the length of the target month.
  void shiftMonth(int months) {
    final current = ref.read(calendarDayProvider);
    final target = DateTime(current.year, current.month + months);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    selectDay(
      DateTime(target.year, target.month, current.day.clamp(1, lastDay)),
    );
  }

  /// Moves an occurrence dropped in the week view to [slot] —
  /// on a series as far as [scope] reaches. "This and all following" from the very
  /// first occurrence is the whole series.
  Future<void> moveOccurrence(
    Occurrence occurrence,
    WeekSlot slot, {
    SeriesScope scope = .wholeSeries,
  }) async {
    if (!movesOccurrence(occurrence, slot)) return;
    final calendars = ref.read(calendarRepositoryProvider);
    final event = occurrence.event;
    final moved = movedTime(occurrence, slot);
    final from = occurrence.isSeries ? occurrence.originalStart : null;
    final reach = switch (from) {
      null => SeriesScope.wholeSeries,
      final from
          when scope == .thisAndFollowing && nothingBefore(event, from) =>
        SeriesScope.wholeSeries,
      _ => scope,
    };
    // `from` is there whenever the reach is not the whole series.
    switch ((reach, from)) {
      case (SeriesScope.onlyThis, final from?):
        // As the editor does it: the occurrence leaves the series and stands on its
        // own at the new time.
        await calendars.cancelOccurrence(event, from);
        await calendars.createEvent(
          calendarId: event.calendarId,
          draft: draftOf(event, timeOf(moved, series: false)).single(),
        );
      case (SeriesScope.thisAndFollowing, final from?):
        await calendars.splitSeries(
          event: event,
          from: from,
          calendarId: event.calendarId,
          draft: draftOf(event, timeOf(moved, series: true)),
        );
      case _ when occurrence.isSeries:
        await calendars.updateEvent(
          event,
          draftOf(event, seriesTimeAfterMove(event, occurrence, moved)),
        );
      case _:
        await calendars.updateEvent(
          event,
          draftOf(event, timeOf(moved, series: false)),
        );
    }
  }

  /// Shows or hides a calendar — the choice survives a restart.
  Future<void> toggleCalendar(String calendarId) {
    final hidden = {...ref.read(preferencesProvider).hiddenCalendars};
    if (!hidden.remove(calendarId)) hidden.add(calendarId);
    return ref.read(preferencesStoreProvider).setHiddenCalendars(hidden);
  }

  void toggleTag(String id) =>
      ref.read(tagFilterStoreProvider).toggle(_area, id);

  void clearTags() => ref.read(tagFilterStoreProvider).clear(_area);
}
