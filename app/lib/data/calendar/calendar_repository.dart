import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

import '../../core/api/generated/export.dart'
    show
        ColorToken,
        IcsImportRequest,
        IcsImportResult,
        ImportCalendar,
        SubscriptionPreview,
        SubscriptionPreviewRequest;
import '../../core/api/hiwiski_api.dart';
import '../../core/db/hiwiski_database.dart';
import '../../domain/common/recurrence_spec.dart';
import '../../domain/common/rrule_parts.dart';
import '../../core/common/ids.dart';
import '../../core/sync/local_writes.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/common/wire.dart';
import '../../domain/common/calendar_days.dart';
import '../../domain/calendar/calendar_items.dart';
import 'event_rows.dart';
import '../../domain/calendar/event_draft.dart';
import '../../domain/calendar/import_target.dart';
import '../../domain/calendar/occurrence.dart';
import '../../domain/calendar/reschedule.dart';
import '../../domain/common/change.dart';
import '../../domain/tags/tag.dart';

/// Calendars, events, subscriptions and ICS links — **always against the local database**.
class CalendarRepository {
  /// [deviceTimeZone] is the zone a new timed event is created in.
  CalendarRepository({
    required this._db,
    required this._writes,
    required this._api,
    required this._sync,
    required this._currentMemberId,
    required this.deviceTimeZone,
  });

  final HiwiskiDatabase _db;
  final LocalWrites _writes;
  final HiwiskiApi _api;
  final SyncTrigger _sync;
  final String Function() _currentMemberId;

  /// The device's time zone, as an IANA name ("Europe/Berlin").
  final String deviceTimeZone;

  String get _ownerId => _currentMemberId();

  /// For what changes on the server and comes back through the sync — an import, a
  /// subscription refreshed. What is written here nudges the sync by itself.
  void _nudge() =>
      // The sync reports its own failures: banner, retry.
      _sync.syncNow().ignore();

  // --- Reading -------------------------------------------------------------------

  Stream<List<Calendar>> watchCalendars() =>
      (_db.select(_db.calendars)
            ..where((row) => row.deletedAt.isNull())
            ..orderBy([
              (row) => OrderingTerm.asc(row.position),
              (row) => OrderingTerm.asc(row.name),
            ]))
          .watch()
          .map((rows) => [for (final row in rows) row.toDomain()]);

  Stream<List<CalendarEvent>> watchEvents() =>
      (_db.select(_db.events)..where((row) => row.deletedAt.isNull()))
          .watch()
          .map((rows) => [for (final row in rows) row.toDomain()]);

  Stream<CalendarEvent?> watchEvent(String eventId) =>
      (_db.select(_db.events)..where((row) => row.id.equals(eventId)))
          .watchSingleOrNull()
          .map((row) => row?.toDomain());

  /// The day an event starts on — across all three time forms; `null` if it is gone.
  ///
  /// For a series, the first event: computing the expansion here once more just to
  /// pick a date would be a second place for the same rule.
  Future<DateTime?> startDayOf(String eventId) async {
    final row = await (_db.select(
      _db.events,
    )..where((row) => row.id.equals(eventId))).getSingleOrNull();
    if (row == null) return null;
    final start =
        row.startsAt ??
        row.startDate ??
        DateTime.tryParse(row.localStart ?? '');
    return start == null ? null : DateTime(start.year, start.month, start.day);
  }

  Stream<List<CalendarSubscription>> watchSubscriptions() =>
      (_db.select(_db.calendarSubscriptions)
            ..where((row) => row.deletedAt.isNull()))
          .watch()
          .map((rows) => [for (final row in rows) row.toDomain()]);

  Stream<List<CalendarFeed>> watchFeeds() =>
      (_db.select(_db.calendarFeeds)..where((row) => row.deletedAt.isNull()))
          .watch()
          .map((rows) => [for (final row in rows) row.toDomain()]);

  // --- Calendars -----------------------------------------------------------------

  Future<String> createCalendar({
    required String name,
    required String colorToken,
    List<String> tags = const [],
    int? defaultReminderMinutes,
  }) async {
    final id = newId();
    await _writes.run(
      (write) => write.create(
        _db.calendars,
        CalendarRow(
          id: id,
          ownerId: _ownerId,
          version: 0,
          name: name,
          colorToken: colorToken,
          kind: CalendarKinds.local,
          position: 0,
          tags: tags.join(','),
          defaultReminderMinutes: defaultReminderMinutes,
        ),
        fields: {
          WireFields.name: name,
          WireFields.colorToken: colorToken,
          WireFields.kind: CalendarKinds.local,
          WireFields.tags: tags,
          WireFields.defaultReminderMinutes: ?defaultReminderMinutes,
        },
        label: name,
      ),
    );
    return id;
  }

  /// Changes a calendar — each field only if given.
  Future<void> updateCalendar(
    Calendar calendar, {
    String? name,
    String? colorToken,
    List<String>? tags,
    Change<int?>? defaultReminderMinutes,
  }) async {
    final fields = <String, dynamic>{
      WireFields.name: ?name,
      WireFields.colorToken: ?colorToken,
      WireFields.tags: ?tags,
      if (defaultReminderMinutes != null)
        WireFields.defaultReminderMinutes: defaultReminderMinutes.value,
    };
    if (fields.isEmpty) return;
    await _writes.run(
      (write) => write.change(
        _db.calendars,
        CalendarsCompanion(
          name: _string(fields, WireFields.name),
          colorToken: _string(fields, WireFields.colorToken),
          tags: switch (fields[WireFields.tags]) {
            final List<dynamic> tags => Value(tags.join(',')),
            _ => const Value.absent(),
          },
          defaultReminderMinutes: defaultReminderMinutes == null
              ? const Value.absent()
              : Value(defaultReminderMinutes.value),
        ),
        id: calendar.id,
        version: calendar.version,
        fields: fields,
        label: calendar.name,
      ),
    );
  }

  /// A deleted calendar takes its events with it.
  ///
  /// Locally right away as well — the server does the same and reports it back through
  /// the log, but until then the events of a deleted calendar would still be on screen.
  Future<void> deleteCalendar(Calendar calendar) async {
    final now = clock.now();
    await _writes.run((write) async {
      final deleted = await write.delete(
        _db.calendars,
        id: calendar.id,
        version: calendar.version,
        label: calendar.name,
        at: now,
      );
      await write.cascade(
        deleted,
        _db.events,
        EventsCompanion(deletedAt: Value(now)),
        where: (row) => row.calendarId.equals(calendar.id),
      );
      await write.cascade(
        deleted,
        _db.calendarSubscriptions,
        CalendarSubscriptionsCompanion(deletedAt: Value(now)),
        where: (row) => row.calendarId.equals(calendar.id),
      );
    });
  }

  // --- Events --------------------------------------------------------------------

  Future<String> createEvent({
    required String calendarId,
    required EventDraft draft,
  }) => _createEvent(calendarId, _eventFields(draft));

  Future<String> _createEvent(
    String calendarId,
    Map<String, dynamic> fields,
  ) async {
    final id = newId();
    await _writes.run(
      (write) => write.create(
        _db.events,
        EventsCompanion.insert(
          id: id,
          ownerId: _ownerId,
          calendarId: calendarId,
          title: Value(fields[WireFields.title] as String? ?? ''),
          description: Value(fields[WireFields.description] as String?),
          location: Value(fields[WireFields.location] as String?),
          timeForm: Value(
            fields[WireFields.timeForm] as String? ?? TimeForms.timed,
          ),
          startsAt: Value(_date(fields[WireFields.startsAt])),
          endsAt: Value(_date(fields[WireFields.endsAt])),
          startDate: Value(_date(fields[WireFields.startDate])),
          endDate: Value(_date(fields[WireFields.endDate])),
          localStart: Value(fields[WireFields.localStart] as String?),
          localEnd: Value(fields[WireFields.localEnd] as String?),
          timeZone: Value(fields[WireFields.timeZone] as String?),
          rrule: Value(fields[WireFields.rrule] as String?),
          attendees: Value(
            (fields[WireFields.attendees] as List?)?.join(',') ?? '',
          ),
          tags: Value((fields[WireFields.tags] as List?)?.join(',') ?? ''),
          reminderMinutes: Value(
            (fields[WireFields.reminderMinutes] as num?)?.toInt(),
          ),
          exceptions: fields.containsKey(WireFields.exceptions)
              ? Value(jsonEncode(fields[WireFields.exceptions]))
              : const Value.absent(),
        ),
        fields: fields,
        containerType: EntityTypes.calendar,
        containerId: calendarId,
        after: calendarId,
        label: fields[WireFields.title] as String? ?? '',
      ),
    );
    return id;
  }

  /// Writes the whole event as the editor shows it.
  /// [calendarId] moves the event to another calendar; left out, it stays where it is.
  /// Saves [draft] over [event] — **only the fields that differ go out**.
  ///
  /// The form hands over the whole event. Sent as a whole, a field nobody touched would
  /// overwrite what another device changed meanwhile, and the history would list every
  /// field as changed.
  Future<void> updateEvent(
    CalendarEvent event,
    EventDraft draft, {
    String? calendarId,
  }) {
    final stored = _storedEventFields(event);
    final fields = <String, dynamic>{
      for (final MapEntry(:key, :value) in _eventFields(draft).entries)
        if (!_sameWireValue(stored[key], value)) key: value,
      if (calendarId != null && calendarId != event.calendarId)
        WireFields.calendarId: calendarId,
    };
    return fields.isEmpty ? Future.value() : _updateEvent(event, fields);
  }

  /// Who takes part: members and groups.
  Future<void> setEventAttendees(CalendarEvent event, List<String> attendees) =>
      _updateEvent(event, {WireFields.attendees: attendees});

  /// The note alone — a box ticked in it.
  Future<void> setEventDescription(CalendarEvent event, String? description) =>
      _updateEvent(event, {WireFields.description: description});

  Future<void> setEventTags(CalendarEvent event, List<String> tags) =>
      _updateEvent(event, {WireFields.tags: tags});

  Future<void> _updateEvent(
    CalendarEvent event,
    Map<String, dynamic> fields,
  ) async {
    await _writes.run(
      (write) => write.change(
        _db.events,
        _localEvent(fields),
        id: event.id,
        version: event.version,
        fields: fields,
        containerType: EntityTypes.calendar,
        containerId:
            fields[WireFields.calendarId] as String? ?? event.calendarId,
        label: event.title,
      ),
    );
  }

  Future<void> deleteEvent(CalendarEvent event) async {
    await _writes.run(
      (write) => write.delete(
        _db.events,
        id: event.id,
        version: event.version,
        label: event.title,
      ),
    );
  }

  /// Cancels **one** occurrence of a series.
  ///
  /// The exception is **added, not replaced**: two devices that cancel different
  /// occurrences while offline both get through. That is exactly what an earlier version forgot
  /// here. So the same merge is done locally as on the server — otherwise
  /// the device would show a state until the next sync that does not exist.
  Future<void> cancelOccurrence(CalendarEvent event, DateTime originalStart) =>
      _addException(event, originalStart, {
        EventExceptionFields.cancelled: true,
      });

  Future<void> _addException(
    CalendarEvent event,
    DateTime originalStart,
    Map<String, dynamic> exception,
  ) async {
    final key = EventExpander.formatKey(originalStart);

    await _writes.run((write) async {
      // Merged into the row as it is now, not into the snapshot handed in: two quick
      // cancels from the same snapshot lost the first one here until the next pull.
      final current = await (_db.select(
        _db.events,
      )..where((row) => row.id.equals(event.id))).getSingleOrNull();
      final merged = Map<String, dynamic>.from(
        EventExpander.decodeExceptions(current?.exceptions ?? event.exceptions),
      )..[key] = exception;
      await write.change(
        _db.events,
        EventsCompanion(exceptions: Value(jsonEncode(merged))),
        id: event.id,
        version: event.version,
        // Only the one entry goes out. The server adds it; whoever cancels a different
        // day at the same time does not lose theirs.
        fields: {
          WireFields.exceptions: {key: exception},
        },
        containerType: EntityTypes.calendar,
        containerId: event.calendarId,
        label: event.title,
      );
    });
  }

  /// Cuts a series off **from** this occurrence on and creates the rest anew.
  ///
  /// "This and all following" is not a field type of its own but two steps: the old
  /// series ends the day before, a new one starts here. Every calendar in the world does
  /// it this way, and anything else would need a series pointer that the model does not
  /// have.
  ///
  /// The new part goes into [calendarId] — the one the editor shows. It takes along
  /// what belongs to it: the occurrences a `COUNT` has left, and the exceptions from
  /// [from] on (moved by as much as the edit moved the start). Before, a `COUNT=10`
  /// series split at the 6th ran 15 times, and a cancelled day after the split came
  /// back.
  ///
  /// [carry] places such an exception, by its original start, in the new part, or
  /// leaves it behind with `null` — for a move that shifts some weekdays of the series
  /// and not others. [cancelled] are occurrences of the new part that the old one
  /// keeps, so they would show twice.
  Future<String> splitSeries({
    required CalendarEvent event,
    required DateTime from,
    required String calendarId,
    required EventDraft draft,
    DateTime? Function(DateTime original)? carry,
    Iterable<DateTime> cancelled = const [],
  }) async {
    final start = switch (draft.time) {
      RecurringEvent(:final start) => start,
      AllDayEvent(:final start) => start,
      TimedEvent(:final start) => start,
    };
    final shift = _wallClock(start).difference(_wallClock(from));
    final place =
        carry ?? (original) => _fromWallClock(_wallClock(original).add(shift));
    final carried = <String, dynamic>{
      for (final MapEntry(:key, :value) in EventExpander.decodeExceptions(
        event.exceptions,
      ).entries)
        if (DateTime.tryParse(key) case final original?
            when !original.isBefore(from))
          if (place(original) case final placed?)
            EventExpander.formatKey(placed): value,
      for (final day in cancelled)
        EventExpander.formatKey(day): {EventExceptionFields.cancelled: true},
    };
    final rrule = draft.rrule == event.rrule
        ? remainingRule(event, from)
        : draft.rrule;

    await truncateSeries(event, from);
    return _createEvent(calendarId, {
      ..._eventFields(draft),
      WireFields.rrule: rrule,
      if (carried.isNotEmpty) WireFields.exceptions: carried,
    });
  }

  /// A series after its [occurrence] moved to [moved] to another day or time: the
  /// whole series, or with [from] what is left of it from there on. Its time and rule
  /// are what [seriesAfterMove] makes of them, the rest is [draft].
  ///
  /// A drop in the week view and a new date in the editor both come here, so a series
  /// moves the same way from either.
  Future<void> moveSeries({
    required CalendarEvent event,
    required Occurrence occurrence,
    required ({DateTime start, DateTime end, bool allDay}) moved,
    required EventDraft draft,
    String? calendarId,
    DateTime? from,
  }) async {
    final series = seriesAfterMove(event, occurrence, moved, from: from);
    final written = draft.withTime(series.time).withRule(series.rrule);
    if (from != null) {
      await splitSeries(
        event: event,
        from: from,
        calendarId: calendarId ?? event.calendarId,
        draft: written,
        carry: series.carry,
        cancelled: series.cancelled,
      );
      return;
    }
    await updateEvent(event, written, calendarId: calendarId);
    for (final day in series.cancelled) {
      await cancelOccurrence(event, day);
    }
  }

  static DateTime _wallClock(DateTime time) => .utc(
    time.year,
    time.month,
    time.day,
    time.hour,
    time.minute,
    time.second,
  );

  static DateTime _fromWallClock(DateTime wall) => .new(
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
    wall.second,
  );

  /// Lets the series end on the day before [from].
  ///
  /// For "this and all following" when **deleting**: then the series should only be cut
  /// off and nothing new created.
  ///
  /// The series ends one second before [from] — exactly, as an instant. It used to end at
  /// 23:59:59 **UTC** of the day before, which in Berlin let a 01:00 series keep the
  /// occurrence on [from] — doubled by the new part of a split — and in New York cut off
  /// an evening occurrence the day before.
  Future<void> truncateSeries(CalendarEvent event, DateTime from) {
    final until =
        '${RruleParts.until}='
        '${RecurrenceSpec.untilInstant(from.subtract(const Duration(seconds: 1)))}';
    return _updateEvent(event, {
      WireFields.rrule: _withUntil(event.rrule ?? '', until),
    });
  }

  static String _withUntil(String rrule, String until) {
    final clean = rrule.replaceFirst(
      RegExp('^${RruleParts.prefix}', caseSensitive: false),
      '',
    );
    final parts =
        clean
            .split(';')
            .where(
              (part) => !part.toUpperCase().startsWith('${RruleParts.until}='),
            )
            .where(
              (part) => !part.toUpperCase().startsWith('${RruleParts.count}='),
            )
            .toList()
          ..add(until);
    return parts.join(';');
  }

  /// The fields of a whole event, as they go out.
  Map<String, dynamic> _eventFields(EventDraft draft) => {
    WireFields.title: draft.title,
    WireFields.description: draft.description,
    WireFields.location: draft.location,
    WireFields.rrule: draft.rrule,
    WireFields.attendees: draft.attendees,
    WireFields.tags: draft.tags,
    WireFields.reminderMinutes: draft.reminderMinutes,
    ..._timeFields(draft.time),
    // A series of whole days repeats in the zone its end ("until") was picked in.
    if (draft.time is AllDayEvent && (draft.rrule ?? '').isNotEmpty)
      WireFields.timeZone: deviceTimeZone,
  };

  /// [event] as it is stored, in the same encoding as [_eventFields] — what an edit is
  /// compared against.
  Map<String, dynamic> _storedEventFields(CalendarEvent event) => {
    WireFields.title: event.title,
    WireFields.description: event.description,
    WireFields.location: event.location,
    WireFields.rrule: (event.rrule ?? '').isEmpty ? null : event.rrule,
    WireFields.attendees: tagIdsOf(event.attendees),
    WireFields.tags: tagIdsOf(event.tags),
    WireFields.reminderMinutes: event.reminderMinutes,
    WireFields.timeForm: event.timeForm,
    WireFields.startsAt: event.startsAt?.toUtc().toIso8601String(),
    WireFields.endsAt: event.endsAt?.toUtc().toIso8601String(),
    WireFields.startDate: switch (event.startDate) {
      final date? => localDate(date),
      null => null,
    },
    WireFields.endDate: switch (event.endDate) {
      final date? => localDate(date),
      null => null,
    },
    WireFields.localStart: event.localStart,
    WireFields.localEnd: event.localEnd,
    WireFields.timeZone: event.timeZone,
  };

  static bool _sameWireValue(Object? stored, Object? sent) =>
      stored is List && sent is List
      ? const ListEquality<Object?>().equals(stored, sent)
      : stored == sent;

  /// Only the fields of the chosen time form carry a value; the others are cleared.
  Map<String, dynamic> _timeFields(EventTime time) => switch (time) {
    AllDayEvent(:final start, :final end) => {
      WireFields.timeForm: TimeForms.allDay,
      WireFields.startDate: localDate(start),
      WireFields.endDate: localDate(end),
      WireFields.startsAt: null,
      WireFields.endsAt: null,
      WireFields.localStart: null,
      WireFields.localEnd: null,
      WireFields.timeZone: null,
    },
    RecurringEvent(:final start, :final end) => {
      WireFields.timeForm: TimeForms.recurring,
      WireFields.localStart: localStamp(start),
      WireFields.localEnd: localStamp(end),
      WireFields.timeZone: deviceTimeZone,
      WireFields.startsAt: null,
      WireFields.endsAt: null,
      WireFields.startDate: null,
      WireFields.endDate: null,
    },
    TimedEvent(:final start, :final end) => {
      WireFields.timeForm: TimeForms.timed,
      WireFields.startsAt: start.toUtc().toIso8601String(),
      WireFields.endsAt: end.toUtc().toIso8601String(),
      WireFields.startDate: null,
      WireFields.endDate: null,
      WireFields.localStart: null,
      WireFields.localEnd: null,
      WireFields.timeZone: null,
    },
  };

  /// The local row's side of [fields].
  EventsCompanion _localEvent(Map<String, dynamic> fields) => .new(
    calendarId: _string(fields, WireFields.calendarId),
    title: _string(fields, WireFields.title),
    description: _nullableString(fields, WireFields.description),
    location: _nullableString(fields, WireFields.location),
    timeForm: _string(fields, WireFields.timeForm),
    startsAt: _nullableDate(fields, WireFields.startsAt),
    endsAt: _nullableDate(fields, WireFields.endsAt),
    startDate: _nullableDate(fields, WireFields.startDate),
    endDate: _nullableDate(fields, WireFields.endDate),
    localStart: _nullableString(fields, WireFields.localStart),
    localEnd: _nullableString(fields, WireFields.localEnd),
    timeZone: _nullableString(fields, WireFields.timeZone),
    rrule: _nullableString(fields, WireFields.rrule),
    attendees: fields.containsKey(WireFields.attendees)
        ? Value((fields[WireFields.attendees] as List?)?.join(',') ?? '')
        : const Value.absent(),
    tags: fields.containsKey(WireFields.tags)
        ? Value((fields[WireFields.tags] as List?)?.join(',') ?? '')
        : const Value.absent(),
    reminderMinutes: fields.containsKey(WireFields.reminderMinutes)
        ? Value((fields[WireFields.reminderMinutes] as num?)?.toInt())
        : const Value.absent(),
  );

  // --- Subscriptions -------------------------------------------------------------

  /// Creates the subscription **and** its external calendar.
  ///
  /// Both in one go and in this order: the subscription belongs to the calendar, and a
  /// mutation whose container has not gone through yet must depend on it.
  Future<String> createSubscription({
    required String name,
    required String url,
    required String colorToken,
    required String syncInterval,
    required String targetKind,
  }) async {
    final calendarId = newId();
    final subscriptionId = newId();

    await _writes.run((write) async {
      await write.create(
        _db.calendars,
        CalendarRow(
          id: calendarId,
          ownerId: _ownerId,
          version: 0,
          name: name,
          colorToken: colorToken,
          // EXTERNAL: read-only, and **not** offered when creating an event.
          kind: CalendarKinds.external,
          position: 0,
          tags: '',
        ),
        fields: {
          WireFields.name: name,
          WireFields.colorToken: colorToken,
          WireFields.kind: CalendarKinds.external,
        },
        label: name,
      );
      await write.create(
        _db.calendarSubscriptions,
        CalendarSubscriptionRow(
          id: subscriptionId,
          ownerId: _ownerId,
          version: 0,
          calendarId: calendarId,
          name: name,
          url: url,
          targetKind: targetKind,
          syncInterval: syncInterval,
          importedCount: 0,
        ),
        fields: {
          WireFields.name: name,
          WireFields.url: url,
          WireFields.targetKind: targetKind,
          WireFields.syncInterval: syncInterval,
        },
        containerType: EntityTypes.calendar,
        containerId: calendarId,
        after: calendarId,
        label: name,
      );
    });
    return subscriptionId;
  }

  /// **A deleted subscription takes its calendar with it**.
  ///
  /// In an earlier version it stayed behind: afterwards it sat empty in the picker for a new event
  /// and accepted nothing there, being external.
  Future<void> deleteSubscription(CalendarSubscription subscription) async {
    final now = clock.now();
    await _writes.run((write) async {
      final deleted = await write.delete(
        _db.calendarSubscriptions,
        id: subscription.id,
        version: subscription.version,
        label: subscription.name,
        at: now,
      );
      await write.cascade(
        deleted,
        _db.calendars,
        CalendarsCompanion(deletedAt: Value(now)),
        where: (row) => row.id.equals(subscription.calendarId),
      );
      await write.cascade(
        deleted,
        _db.events,
        EventsCompanion(deletedAt: Value(now)),
        where: (row) => row.calendarId.equals(subscription.calendarId),
      );
    });
  }

  // --- ICS links -----------------------------------------------------------------

  Future<String> createFeed({
    required String name,
    required List<String> calendarIds,
    required String contentMode,
  }) async {
    final id = newId();
    // The token is rolled on the device, like the id: it travels through sync in plain
    // text so the address can be shown on every one of the owner's devices.
    final token = newId().replaceAll('-', '');

    await _writes.run(
      (write) => write.create(
        _db.calendarFeeds,
        CalendarFeedRow(
          id: id,
          ownerId: _ownerId,
          version: 0,
          name: name,
          calendarIds: calendarIds.join(','),
          contentMode: contentMode,
          token: token,
        ),
        fields: {
          WireFields.name: name,
          WireFields.calendarIds: calendarIds,
          WireFields.contentMode: contentMode,
          WireFields.token: token,
        },
        label: name,
      ),
    );
    return id;
  }

  Future<void> deleteFeed(CalendarFeed feed) async {
    await _writes.run(
      (write) => write.delete(
        _db.calendarFeeds,
        id: feed.id,
        version: feed.version,
        label: feed.name,
      ),
    );
  }

  // --- Helpers -------------------------------------------------------------------

  // --- Over REST -----------------------------------------------------------------

  /// The "sync now" button.
  ///
  /// It is the only calendar path that goes over REST: the sync runs on the server
  /// because a subscription should keep running even when no device is online.
  /// Pull once afterwards — the new events arrive through sync.
  ///
  /// The pull is a nudge: awaited, a failing push or pull of something else entirely
  /// came out of here as if the refresh had failed.
  Future<void> refreshSubscription(String subscriptionId) async {
    await HiwiskiApi.run(
      () => _api.calendar.refreshCalendarSubscription(
        subscriptionId: subscriptionId,
      ),
    );
    _nudge();
  }

  /// What an ICS address — or a file's content — holds, before subscribing or
  /// importing. Over REST, nothing is stored.
  Future<SubscriptionPreview> previewSubscription({String? url, String? ics}) =>
      HiwiskiApi.run(
        () => _api.calendar.previewCalendarSubscription(
          body: SubscriptionPreviewRequest(url: url, ics: ics),
        ),
      );

  /// A one-off import of an `.ics` file — its content, or an address fetched
  /// **once** — into one of our calendars or a new one. Pull once afterwards: the
  /// events (and a new calendar) arrive through sync like every other change.
  Future<IcsImportResult> importIcs(
    ImportTarget target, {
    String? ics,
    String? url,
  }) async {
    final calendarId = switch (target) {
      ExistingCalendar(:final calendarId) => calendarId,
      // The id is ours: the server creates the calendar under it.
      NewCalendar() => newId(),
    };
    final result = await HiwiskiApi.run(
      () => _api.calendar.importIcsFile(
        calendarId: calendarId,
        body: IcsImportRequest(
          ics: ics,
          url: url,
          newCalendar: switch (target) {
            NewCalendar(:final name, :final colorToken, :final locked) =>
              ImportCalendar(
                name: name,
                colorToken: ColorToken.fromJson(colorToken),
                locked: locked,
              ),
            ExistingCalendar() => null,
          },
        ),
      ),
    );
    // A nudge, not awaited: an import the server accepted, followed by a failing sync,
    // showed the import as failed — and the member imported again.
    _nudge();
    return result;
  }

  static Value<String> _string(Map<String, dynamic> fields, String name) =>
      fields.containsKey(name)
      ? .new(fields[name] as String? ?? '')
      : const .absent();

  static Value<String?> _nullableString(
    Map<String, dynamic> fields,
    String name,
  ) => fields.containsKey(name)
      ? .new(fields[name] as String?)
      : const .absent();

  static Value<DateTime?> _nullableDate(
    Map<String, dynamic> fields,
    String name,
  ) => fields.containsKey(name) ? .new(_date(fields[name])) : const .absent();

  static DateTime? _date(Object? value) =>
      value == null ? null : .tryParse(value.toString());
}

extension on CalendarRow {
  Calendar toDomain() => .new(
    id: id,
    ownerId: ownerId,
    version: version,
    deletedAt: deletedAt,
    name: name,
    colorToken: colorToken,
    kind: kind,
    position: position,
    tags: tags,
    defaultReminderMinutes: defaultReminderMinutes,
  );
}

extension on CalendarSubscriptionRow {
  CalendarSubscription toDomain() => .new(
    id: id,
    ownerId: ownerId,
    version: version,
    deletedAt: deletedAt,
    calendarId: calendarId,
    name: name,
    url: url,
    targetKind: targetKind,
    targetListId: targetListId,
    syncInterval: syncInterval,
    lastSyncAt: lastSyncAt,
    lastError: lastError,
    importedCount: importedCount,
  );
}

extension on CalendarFeedRow {
  CalendarFeed toDomain() => .new(
    id: id,
    ownerId: ownerId,
    version: version,
    deletedAt: deletedAt,
    name: name,
    calendarIds: calendarIds,
    contentMode: contentMode,
    token: token,
  );
}
