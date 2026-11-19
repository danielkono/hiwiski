import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/domain/common/change.dart';
import 'package:hiwiski/domain/common/recurrence.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:hiwiski/core/sync/local_writes.dart';
import 'package:hiwiski/core/sync/outbox.dart';
import 'package:hiwiski/core/sync/sync_engine.dart';
import 'package:hiwiski/domain/calendar/event_draft.dart';
import 'package:hiwiski/data/calendar/calendar_repository.dart';
import 'package:hiwiski/domain/todo/todo_items.dart';
import 'package:hiwiski/data/todo/todo_repository.dart';
import 'package:hiwiski/data/wiki/wiki_repository.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';

import 'support/fakes.dart';

/// **Typed updates send what the field maps sent.** The screens no longer know the
/// wire names; what reaches the outbox — and so the server — must not change.
void main() {
  late HiwiskiDatabase db;
  late Outbox outbox;

  setUp(() {
    db = HiwiskiDatabase(NativeDatabase.memory());
    outbox = Outbox(db);
  });

  tearDown(() => db.close());

  Future<Map<String, dynamic>> lastFields(String id) async {
    final entries = await (db.select(
      db.outboxEntries,
    )..where((row) => row.entityId.equals(id))).get();
    return jsonDecode(entries.last.fields) as Map<String, dynamic>;
  }

  group('task', () {
    late TodoRepository todos;

    setUp(() {
      todos = TodoRepository(
        db: db,
        writes: LocalWrites(db: db, outbox: outbox, sync: _NoSync()),
        currentMemberId: () => 'anna',
      );
    });

    Future<Todo> read(String id) async => (await todos.watchTodo(id).first)!;

    test('only the given fields go out', () async {
      final listId = await todos.createList(name: 'Home', kind: 'STANDARD');
      final id = await todos.createTodo(listId: listId, title: 'Bins');

      await todos.updateTodo(await read(id), title: 'Bins out');

      expect(await lastFields(id), equals({'title': 'Bins out'}));
    });

    test('a date goes out as a date, and Change(null) clears it', () async {
      final listId = await todos.createList(name: 'Home', kind: 'STANDARD');
      final id = await todos.createTodo(listId: listId, title: 'Bins');

      await todos.updateTodo(
        await read(id),
        dueDate: Change(DateTime(2026, 10, 7)),
      );
      expect(await lastFields(id), equals({'dueDate': '2026-10-07'}));
      expect((await read(id)).dueDate, equals(DateTime(2026, 10, 7)));

      await todos.updateTodo(await read(id), dueDate: const Change(null));
      expect(await lastFields(id), equals({'dueDate': null}));
      expect((await read(id)).dueDate, isNull);
    });

    test('nothing given, nothing written', () async {
      final listId = await todos.createList(name: 'Home', kind: 'STANDARD');
      final id = await todos.createTodo(listId: listId, title: 'Bins');
      final before = await db.select(db.outboxEntries).get();

      await todos.updateTodo(await read(id));

      expect(await db.select(db.outboxEntries).get(), hasLength(before.length));
    });
  });

  group('event', () {
    late CalendarRepository calendar;

    setUp(() {
      calendar = CalendarRepository(
        db: db,
        writes: LocalWrites(db: db, outbox: outbox, sync: _NoSync()),
        api: HiwiskiApi(tokens: NoTokens()),
        sync: _NoSync(),
        currentMemberId: () => 'anna',
        deviceTimeZone: 'Europe/Berlin',
      );
    });

    EventDraft draft(EventTime time, {String? rrule}) => .new(
      title: 'Dentist',
      time: time,
      rrule: rrule,
      attendees: const ['anna'],
    );

    test('a timed event clears the other two forms', () async {
      final id = await calendar.createEvent(
        calendarId: 'c1',
        draft: draft(
          TimedEvent(
            DateTime.utc(2026, 10, 7, 8),
            DateTime.utc(2026, 10, 7, 9),
          ),
        ),
      );

      expect(
        await lastFields(id),
        equals({
          'title': 'Dentist',
          'description': null,
          'location': null,
          'rrule': null,
          'attendees': ['anna'],
          'tags': <String>[],
          'reminderMinutes': null,
          'timeForm': 'TIMED',
          'startsAt': '2026-10-07T08:00:00.000Z',
          'endsAt': '2026-10-07T09:00:00.000Z',
          'startDate': null,
          'endDate': null,
          'localStart': null,
          'localEnd': null,
          'timeZone': null,
        }),
      );
    });

    // "This and all following" from 10 October on a daily 01:00 series: the old part
    // ends before the occurrence on the 10th — not at 23:59:59 UTC of the 9th, which in
    // Berlin is 01:59 on the 10th and kept it, next to the new part's copy.
    test('cutting a series keeps the occurrence it is cut at out', () async {
      tzdata.initializeTimeZones();
      final id = await calendar.createEvent(
        calendarId: 'c1',
        draft: draft(
          RecurringEvent(DateTime(2026, 10, 1, 1), DateTime(2026, 10, 1, 2)),
          rrule: 'FREQ=DAILY',
        ),
      );
      final event = (await calendar.watchEvent(id).first)!;

      await calendar.truncateSeries(event, DateTime(2026, 10, 10, 1));

      final cut = (await calendar.watchEvent(id).first)!;
      final occurrences = const Recurrence().expand(
        rrule: cut.rrule,
        start: DateTime(2026, 10, 1, 1),
        timeZone: 'Europe/Berlin',
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 11, 1),
      );
      expect(occurrences.last, equals(DateTime(2026, 10, 9, 1)));
    });

    test('a series keeps its wall-clock time and the device zone', () async {
      final id = await calendar.createEvent(
        calendarId: 'c1',
        draft: draft(
          RecurringEvent(DateTime(2026, 10, 5, 8), DateTime(2026, 10, 5, 9)),
          rrule: 'FREQ=WEEKLY',
        ),
      );

      final fields = await lastFields(id);
      expect(fields['timeForm'], equals('RECURRING'));
      expect(fields['localStart'], equals('2026-10-05T08:00'));
      expect(fields['timeZone'], equals('Europe/Berlin'));
      expect(fields['startsAt'], isNull);
    });

    test('one occurrence detached from a series is a timed event', () async {
      final series = draft(
        RecurringEvent(DateTime(2026, 10, 5, 8), DateTime(2026, 10, 5, 9)),
        rrule: 'FREQ=WEEKLY',
      );

      final single = series.single();

      expect(single.rrule, isNull);
      expect(single.time, isA<TimedEvent>());
    });

    test('attendees alone go out alone', () async {
      final id = await calendar.createEvent(
        calendarId: 'c1',
        draft: draft(AllDayEvent(DateTime(2026, 10, 7), DateTime(2026, 10, 7))),
      );
      final event = await calendar.watchEvent(id).first;

      await calendar.setEventAttendees(event!, const ['anna', 'ben']);

      expect(
        await lastFields(id),
        equals({
          'attendees': ['anna', 'ben'],
        }),
      );
    });
  });

  group('comment', () {
    test('editing one sends the body, with its carrier', () async {
      final wiki = WikiRepository(
        db: db,
        writes: LocalWrites(db: db, outbox: outbox, sync: _NoSync()),
        api: HiwiskiApi(tokens: NoTokens()),
        currentMemberId: () => 'anna',
      );
      await wiki.addComment(itemType: 'TODO', itemId: 't1', body: 'Bins?');
      final comment = (await wiki.watchComments('TODO', 't1').first).single;

      await wiki.updateComment(comment, body: 'Bins on Tuesday?');

      expect(
        await lastFields(comment.id),
        equals({'body': 'Bins on Tuesday?'}),
      );
      final entry = (await db.select(db.outboxEntries).get()).last;
      expect((entry.containerType, entry.containerId), equals(('TODO', 't1')));
      expect(
        (await wiki.watchComments('TODO', 't1').first).single.body,
        equals('Bins on Tuesday?'),
      );
    });
  });
}

class _NoSync implements SyncTrigger {
  @override
  Future<void> syncNow() async {}
}
