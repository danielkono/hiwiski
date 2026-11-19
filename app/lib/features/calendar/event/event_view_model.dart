import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../core/api/generated/export.dart';
import '../../../domain/access/access_rules.dart';
import '../../../domain/calendar/calendar_items.dart';
import '../../../domain/calendar/calendar_kinds.dart';
import '../../../domain/calendar/occurrence.dart';
import '../../../domain/common/item_ref.dart';
import '../../../domain/tags/tag.dart';
import '../../../domain/wiki/markdown_editing.dart';

part 'event_view_model.g.dart';

/// An event as its page and a link's preview show it.
@immutable
class EventState {
  const EventState({
    required this.event,
    this.calendar,
    this.level,
    this.names = const {},
  });

  final CalendarEvent event;
  final Calendar? calendar;
  final AccessLevel? level;

  /// Members and groups by id — whom the attendees name.
  final Map<String, String> names;

  bool get subscribed => isLockedCalendar(calendar?.kind);

  /// Read-only twice over: from a subscription, or shared with the reader to *read*.
  bool get readOnly => subscribed || !mayWrite(level);

  /// The attendees by name; `—` for one not known.
  List<String> get attendees => [
    for (final id in tagIdsOf(event.attendees)) names[id] ?? '—',
  ];
}

@riverpod
Stream<CalendarEvent?> _event(Ref ref, String eventId) =>
    ref.watch(calendarRepositoryProvider).watchEvent(eventId);

@riverpod
Stream<List<Calendar>> _calendars(Ref ref) =>
    ref.watch(calendarRepositoryProvider).watchCalendars();

@riverpod
Stream<ShareSheet> _shares(Ref ref, String eventId) =>
    ref.watch(accessRepositoryProvider).watchShareSheet(ItemRef.event(eventId));

@riverpod
Stream<List<Member>> _members(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchMembers();

@riverpod
Stream<List<Group>> _groups(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchGroups();

/// An event's page. `null` once the event is gone.
@riverpod
class EventViewModel extends _$EventViewModel {
  @override
  Future<EventState?> build(String eventId) async {
    // From the server — not waited for: offline they may never come.
    final level = ref.watch(_sharesProvider(eventId)).value?.myLevel;
    final groups = ref.watch(_groupsProvider).value ?? const <Group>[];
    final members = ref.watch(_membersProvider).value ?? const <Member>[];
    final event = ref.watch(_eventProvider(eventId).future);
    final calendars = ref.watch(_calendarsProvider.future);
    final row = await event;
    if (row == null) return null;
    return EventState(
      event: row,
      calendar: (await calendars)
          .where((calendar) => calendar.id == row.calendarId)
          .firstOrNull,
      level: level,
      names: {
        for (final group in groups) group.id: group.name,
        for (final member in members) member.id: member.displayName,
      },
    );
  }

  /// Ticks the [index]-th box of the event's note, as on a wiki page.
  Future<void> toggleNoteTask(CalendarEvent event, int index) => ref
      .read(calendarRepositoryProvider)
      .setEventDescription(event, toggleTask(event.description ?? '', index));

  /// Deletes the event — on an occurrence of a series as far as [scope] reaches.
  /// "This and all following" from the very first occurrence is the whole series.
  Future<void> delete(
    CalendarEvent event, {
    Occurrence? occurrence,
    SeriesScope scope = .wholeSeries,
  }) async {
    final calendars = ref.read(calendarRepositoryProvider);
    final from = occurrence?.originalStart;
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
        await calendars.cancelOccurrence(event, from);
      case (SeriesScope.thisAndFollowing, final from?):
        // Only cut off: the rest of the series should go away, not be replaced.
        await calendars.truncateSeries(event, from);
      case _:
        await calendars.deleteEvent(event);
    }
  }
}
