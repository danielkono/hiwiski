import 'dart:async';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show TableUpdateQuery;

import '../../core/db/hiwiski_database.dart';
import '../../core/platform/reminder_scheduler.dart';
import 'event_rows.dart';
import '../../domain/calendar/calendar_reminders.dart';
import '../../domain/calendar/occurrence.dart';

/// The occurrence a reminder is for — where a tap on it leads.
typedef ReminderTarget = ({String eventId, DateTime start});

/// Sets the reminders for every event that has one — its own or its calendar's default.
///
/// Scheduling **always redoes everything**, never patches single entries — the reasoning
/// is at [ReminderScheduler.replaceAll].
class ReminderRepository {
  ReminderRepository({
    required this._db,
    required this._scheduler,
    required this._timeZone,
    required this._words,
  });

  final HiwiskiDatabase _db;
  final ReminderScheduler _scheduler;
  final String _timeZone;

  /// Read on every run: the language may have changed since the last one.
  final ReminderWords Function() _words;

  static const _expander = EventExpander();

  /// How far ahead reminders are scheduled.
  ///
  /// The platforms limit the number of notifications scheduled at once (iOS to 64). A
  /// window instead of "everything" is therefore not thrift but the only approach that
  /// is reliable.
  static const window = Duration(days: 30);

  /// The maximum number that get set.
  static const limit = 60;

  bool get supported => _scheduler.supported;

  Timer? _debounce;
  StreamSubscription<void>? _watch;

  /// Once at sign-in.
  ///
  /// After that the service hooks onto the events table: **reset on every change**
  /// — whether it comes from the device or from a sync does not
  /// matter, and that is exactly why it hangs off the table and not off the UI.
  Future<void> initialize() async {
    if (!_scheduler.supported) return;
    await _scheduler.initialize(_timeZone);

    await _watch?.cancel();
    // Events and calendars: a calendar's default reminder changes its events' ones.
    _watch = _db
        .tableUpdates(TableUpdateQuery.onAllTables([_db.events, _db.calendars]))
        .listen((_) {
          // A sync writes many rows in a row; without the brake, scheduling would be redone
          // for every single one.
          _debounce?.cancel();
          _debounce = Timer(
            const Duration(seconds: 2),
            () =>
                // The runs are queued; a failed one leaves the reminders as they were.
                rescheduleAll().ignore(),
          );
        });
    await rescheduleAll();
  }

  /// One run without the app: a background sync has just written, and nobody watches
  /// the tables there. Nothing is asked of the user — see
  /// [ReminderScheduler.initialize].
  Future<void> rescheduleOnce() async {
    if (!_scheduler.supported) return;
    await _scheduler.initialize(_timeZone, askPermission: false);
    await rescheduleAll();
  }

  Future<void> dispose() async {
    _debounce?.cancel();
    await _watch?.cancel();
  }

  /// The run in progress: runs go one after the other. Two overlapping ones each
  /// cancelled everything and scheduled their own list, and a change landing in
  /// between could leave a stale reminder behind.
  Future<void> _running = Future.value();

  Future<void> rescheduleAll() {
    final run = _running.then((_) => _rescheduleAll());
    _running = run.onError<Object>((_, _) {});
    return run;
  }

  Future<void> _rescheduleAll() async {
    if (!_scheduler.supported) return;

    final defaults = {
      for (final calendar in await (_db.select(
        _db.calendars,
      )..where((row) => row.defaultReminderMinutes.isNotNull())).get())
        calendar.id: calendar.defaultReminderMinutes,
    };
    final events = await (_db.select(
      _db.events,
    )..where((row) => row.deletedAt.isNull())).get();

    final now = clock.now();
    final words = _words();
    final reminders = <PendingReminder>[];
    for (final event in events) {
      final minutes = effectiveReminder(
        event.reminderMinutes,
        defaults[event.calendarId],
      );
      if (minutes == null) continue;
      // A look-ahead window: an hour more or less across a clock change is harmless.
      // ignore: many_lints/avoid_dst_unsafe_date_arithmetic
      final expanded = _expander.expand(event.toDomain(), now, now.add(window));
      for (final occurrence in expanded) {
        final when = occurrence.start.subtract(Duration(minutes: minutes));
        if (when.isBefore(now)) continue;
        reminders.add(
          PendingReminder(
            id: idFor(event.id, occurrence.start),
            title: event.title,
            body: _body(
              reminderWhen(
                (
                  start: occurrence.start,
                  end: occurrence.end,
                  allDay: occurrence.allDay,
                ),
                now: now,
                words: words,
              ),
              event.location,
            ),
            when: when,
            payload: _payload(event.id, occurrence.start),
          ),
        );
      }
    }

    reminders.sort((a, b) => a.when.compareTo(b.when));
    await _scheduler.replaceAll(reminders.take(limit).toList());
  }

  /// A reminder tapped while the app runs: the occurrence it is for.
  Stream<ReminderTarget> get opened =>
      _scheduler.opened.map(_target).where((target) => target != null).cast();

  /// The occurrence whose reminder started the app — once.
  Future<ReminderTarget?> takeLaunchTarget() async =>
      switch (await _scheduler.takeLaunchPayload()) {
        final payload? => _target(payload),
        null => null,
      };

  /// What a tap on a reminder opens: the event and its occurrence's start.
  static String _payload(String eventId, DateTime start) =>
      '$eventId$_payloadSeparator${start.toIso8601String()}';

  static ReminderTarget? _target(String payload) {
    final at = payload.lastIndexOf(_payloadSeparator);
    if (at <= 0) return null;
    final start = DateTime.tryParse(payload.substring(at + 1));
    if (start == null) return null;
    return (eventId: payload.substring(0, at), start: start);
  }

  static const _payloadSeparator = '@';

  static String _body(String when, String? location) =>
      location == null || location.isEmpty ? when : '$when · $location';

  /// An id derived from event and occurrence that fits into 31 bits.
  ///
  /// It must be **stable**: the next rescheduling should give the same reminder the same
  /// id, otherwise it would show up twice. Stable across runs, too — the plugin keeps
  /// the ids over a reboot — so FNV-1a instead of `Object.hash`, which Dart seeds anew
  /// on every start.
  static int idFor(String eventId, DateTime start) {
    int hash = _fnvOffset;
    for (final unit in '$eventId@${start.millisecondsSinceEpoch}'.codeUnits) {
      hash = ((hash ^ unit) * _fnvPrime) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  static const _fnvOffset = 0x811c9dc5;
  static const _fnvPrime = 0x01000193;
}
