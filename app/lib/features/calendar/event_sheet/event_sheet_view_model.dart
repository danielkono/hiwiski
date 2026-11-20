import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../app/stores.dart';
import '../../../core/api/generated/export.dart';
import '../../../core/common/wire.dart';
import '../../../domain/access/access_rules.dart';
import '../../../domain/calendar/calendar_items.dart';
import '../../../domain/calendar/calendar_kinds.dart';
import '../../../domain/calendar/event_draft.dart';
import '../../../domain/calendar/occurrence.dart';
import '../../../domain/calendar/reschedule.dart';
import '../../../domain/common/calendar_days.dart';

part 'event_sheet_view_model.g.dart';

/// "New event" and editing one: the calendars it can go into, and saving it.
@immutable
class EventSheetState {
  const EventSheetState({
    required this.calendars,
    required this.remindersSupported,
    this.shareable = true,
    this.me,
  });

  /// External calendars are not offered when creating an event — in
  /// an earlier version they were offered and accepted nothing.
  final List<Calendar> calendars;

  /// Whether this device can remind at all — otherwise the form says so instead of
  /// offering a switch that does nothing.
  final bool remindersSupported;

  /// Whether the event can be shared — not without a server.
  final bool shareable;

  /// Who is signed in.
  final String? me;

  /// Whether [event] may go into another calendar — a new one anywhere, an existing
  /// one only by its owner: a move hands it to another audience.
  bool mayMove(CalendarEvent? event) =>
      event == null || ownsItem(event.ownerId, me);

  /// A calendar's default reminder — what an event without its own takes.
  int? defaultReminderOf(String? calendarId) => calendars
      .where((calendar) => calendar.id == calendarId)
      .firstOrNull
      ?.defaultReminderMinutes;
}

@riverpod
Stream<List<Calendar>> _calendars(Ref ref) =>
    ref.watch(calendarRepositoryProvider).watchCalendars();

@riverpod
class EventSheetViewModel extends _$EventSheetViewModel {
  @override
  Future<EventSheetState> build() async {
    final remindersSupported = ref.watch(reminderRepositoryProvider).supported;
    final calendars = await ref.watch(_calendarsProvider.future);
    return EventSheetState(
      shareable: ref.watch(sessionProvider.select((s) => s.hasServer)),
      me: ref.watch(sessionProvider.select((s) => s.member?.id)),
      calendars: [
        for (final calendar in calendars)
          if (!isLockedCalendar(calendar.kind)) calendar,
      ],
      remindersSupported: remindersSupported,
    );
  }

  /// The calendar to save into — **the first event must not fail because of an admin
  /// chore**: right after setup there is no calendar yet, and "Save" silently did
  /// nothing. Without one a calendar called [defaultName] is created.
  Future<String> _calendarFor(
    String? calendarId, {
    required String defaultName,
  }) {
    if (calendarId != null) return Future.value(calendarId);
    return ref
        .read(calendarRepositoryProvider)
        .createCalendar(name: defaultName, colorToken: ColorTokens.blue);
  }

  /// A new event, with the shares chosen for it — they go out once the server knows
  /// the event.
  ///
  /// [calendarId] `null`: into a new calendar called [defaultCalendarName].
  Future<void> create({
    required String? calendarId,
    required String defaultCalendarName,
    required EventDraft draft,
    List<WriteShare> shares = const [],
  }) async {
    final access = ref.read(accessRepositoryProvider);
    final calendars = ref.read(calendarRepositoryProvider);
    final id = await calendars.createEvent(
      calendarId: await _calendarFor(
        calendarId,
        defaultName: defaultCalendarName,
      ),
      draft: draft,
    );
    await access.queueShares(
      itemType: EntityTypes.event,
      itemId: id,
      shares: shares,
    );
  }

  /// Saves a change as far as [scope] reaches: "This and all following" from the
  /// very first occurrence is the whole series. [series] is the draft for the whole
  /// series, [draft] the one for what is opened.
  ///
  /// [calendarId] `null`: into a new calendar called [defaultCalendarName].
  Future<void> edit(
    CalendarEvent event, {
    required String? calendarId,
    required String defaultCalendarName,
    required Occurrence? occurrence,
    required EventDraft series,
    required EventDraft draft,
    SeriesScope scope = .wholeSeries,
  }) async {
    final calendars = ref.read(calendarRepositoryProvider);
    final target = await _calendarFor(
      calendarId,
      defaultName: defaultCalendarName,
    );
    final from = occurrence?.originalStart;
    final reach = switch (from) {
      null => SeriesScope.wholeSeries,
      final from
          when scope == .thisAndFollowing && nothingBefore(event, from) =>
        SeriesScope.wholeSeries,
      _ => scope,
    };
    final moved = spanOf(draft.time);
    // `from` is there whenever the reach is not the whole series.
    switch ((reach, from)) {
      case (SeriesScope.onlyThis, final from?):
        // A single occurrence becomes an exception on the series plus an event of its
        // own next to it. There is no "only this one" field, and every calendar in
        // the world does it this way.
        await calendars.cancelOccurrence(event, from);
        await calendars.createEvent(calendarId: target, draft: draft.single());
      // A new date moves the series as a drop in the week view does — with a rule on
      // named days only the day that was moved. The form has already shown that rule;
      // one the member wrote by hand is theirs and is written as it is. Moved by the
      // date alone, the series kept `BYDAY=TH` with its start on a Friday, and the
      // occurrence was gone.
      case (_, final from?)
          when occurrence != null &&
              daysFrom(occurrence.start, moved.start) != 0 &&
              draft.rrule ==
                  ruleAfterMove(
                    event.rrule,
                    original: from,
                    target: moved.start,
                  ):
        await calendars.moveSeries(
          event: event,
          occurrence: occurrence,
          moved: moved,
          draft: draft,
          calendarId: target,
          from: reach == .thisAndFollowing ? from : null,
        );
      case (SeriesScope.thisAndFollowing, final from?):
        await calendars.splitSeries(
          event: event,
          from: from,
          calendarId: target,
          draft: draft,
        );
      case _:
        await calendars.updateEvent(event, series, calendarId: target);
    }
  }
}
