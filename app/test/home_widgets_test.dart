import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/platform/home_widget_bridge.dart';
import 'package:hiwiski/data/home_widgets/home_widget_repository.dart';
import 'package:hiwiski/domain/calendar/calendar_items.dart';
import 'package:hiwiski/core/routing/routes.dart';
import 'package:hiwiski/domain/home_widgets/home_widget_settings.dart';
import 'package:hiwiski/domain/home_widgets/home_widget_snapshots.dart';
import 'package:hiwiski/domain/todo/todo_items.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

/// What the home screen widgets get from the app: their settings, the app's own
/// picture of each widget's content — the same answer the server gives — and where a
/// tap on one leads.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('the agenda', () {
    final family = _calendar('family', 'GREEN');
    final work = _calendar('work', 'RUST');
    final now = DateTime(2026, 11, 12, 14, 5, 30);

    test('runs from now to the end of the last day, in the app order', () {
      final agenda = agendaSnapshot(
        events: [
          _event(
            'piano',
            family.id,
            title: 'Piano',
            timeForm: 'RECURRING',
            localStart: '2026-11-02T16:00',
            localEnd: '2026-11-02T17:00',
            rrule: 'FREQ=WEEKLY;BYDAY=MO,TH',
            // Monday's lesson is cancelled.
            exceptions: {
              '2026-11-16T16:00': {'cancelled': true},
            },
          ),
          _event(
            'holidays',
            family.id,
            title: 'Holidays',
            timeForm: 'ALL_DAY',
            startDate: DateTime(2026, 11, 10),
            endDate: DateTime(2026, 11, 13),
          ),
          _event(
            'over',
            family.id,
            title: 'Over',
            timeForm: 'ALL_DAY',
            startDate: DateTime(2026, 11, 11),
          ),
        ],
        calendars: [family, work],
        calendarIds: const [],
        days: 7,
        now: now,
        timeZone: 'Europe/Berlin',
        position: 41,
      );

      expect(agenda.from, equals('2026-11-12T14:05'));
      expect(agenda.to, equals('2026-11-19T00:00'));
      expect(agenda.position, equals(41));
      expect(agenda.truncated, isFalse);
      // The holidays began before the window and still run; Monday's lesson is
      // cancelled, and next Thursday's lies past the last day.
      expect([
        for (final o in agenda.occurrences) '${o.title} ${o.start}',
      ], equals(['Holidays 2026-11-10T00:00', 'Piano 2026-11-12T16:00']));
      expect(agenda.occurrences.first.colorToken, equals('GREEN'));
      expect(agenda.occurrences.first.allDay, isTrue);
      expect(agenda.occurrences.first.end, equals('2026-11-13T00:00'));
    });

    test('only the chosen calendars, cut at the limit', () {
      final agenda = agendaSnapshot(
        events: [
          for (var day = 13; day <= 16; day++)
            _event(
              'family-$day',
              family.id,
              title: 'Family $day',
              timeForm: 'ALL_DAY',
              startDate: DateTime(2026, 11, day),
            ),
          _event(
            'meeting',
            work.id,
            title: 'Meeting',
            timeForm: 'ALL_DAY',
            startDate: DateTime(2026, 11, 13),
          ),
        ],
        calendars: [family, work],
        calendarIds: [family.id],
        days: 7,
        now: now,
        timeZone: 'Europe/Berlin',
        position: 1,
        limit: 2,
      );

      expect([
        for (final o in agenda.occurrences) o.title,
      ], equals(['Family 13', 'Family 14']));
      expect(agenda.truncated, isTrue);
    });
  });

  group('a list', () {
    test('its open entries in its order, and the counts', () {
      final summary = listSnapshot(
        list: _list('groceries', 'SHOPPING'),
        todos: [
          _todo('milk', 'Milk', position: 2000, amount: 2, unit: 'l'),
          _todo('bread', 'Bread', position: 1000),
          _todo('apples', 'Apples', position: 500, done: true),
          _todo('gone', 'Gone', position: 100, deleted: true),
        ],
        position: 7,
      );

      expect([
        for (final i in summary.items) i.title,
      ], equals(['Bread', 'Milk']));
      expect(summary.openCount, equals(2));
      expect(summary.doneCount, equals(1));
      expect(summary.items.last.unit, equals('l'));
      expect(summary.column, isNull);
      expect(summary.position, equals(7));
    });

    test(
      'a column shows the cards standing in it, as the board derives it',
      () {
        final board = _list(
          'household',
          'KANBAN',
          columns: [
            {'id': 'todo', 'name': 'To do', 'done': false},
            {'id': 'doing', 'name': 'Doing', 'done': false},
            {'id': 'done', 'name': 'Done', 'done': true},
          ],
        );
        final todos = [
          _todo('paint', 'Paint', columnId: 'doing'),
          // Ticked off elsewhere: it stands in the done column.
          _todo('shelf', 'Shelf', columnId: 'doing', done: true),
          // Its column was deleted: it stands in the first open one.
          _todo('lamp', 'Lamp', columnId: 'removed'),
        ];

        final doing = listSnapshot(
          list: board,
          todos: todos,
          columnId: 'doing',
          position: 1,
        );
        final finished = listSnapshot(
          list: board,
          todos: todos,
          columnId: 'done',
          position: 1,
        );
        final first = listSnapshot(
          list: board,
          todos: todos,
          columnId: 'todo',
          position: 1,
        );

        expect([for (final i in doing.items) i.title], equals(['Paint']));
        expect(doing.column?.name, equals('Doing'));
        expect(doing.column?.count, equals(1));
        expect([for (final i in finished.items) i.title], equals(['Shelf']));
        expect([for (final i in first.items) i.title], equals(['Lamp']));
      },
    );

    test('a column the board no longer has counts as none', () {
      final summary = listSnapshot(
        list: _list(
          'household',
          'KANBAN',
          columns: [
            {'id': 'todo', 'name': 'To do', 'done': false},
            {'id': 'done', 'name': 'Done', 'done': true},
          ],
        ),
        todos: [_todo('paint', 'Paint', columnId: 'todo')],
        columnId: 'removed',
        position: 1,
      );

      expect(summary.column, isNull);
      expect([for (final i in summary.items) i.title], equals(['Paint']));
    });
  });

  group('the settings', () {
    test('only what is set up goes to the widgets', () {
      final settings = const HomeWidgetSettings()
          .withConfig(.agenda, const HomeWidgetConfig(days: 3))
          .withConfig(.shopping, const HomeWidgetConfig(listId: 'groceries'))
          // A board without its column is not set up.
          .withConfig(.kanban, const HomeWidgetConfig(listId: 'household'));

      expect(
        settings.toJson(),
        equals({
          'agenda': {'calendarIds': <String>[], 'days': 3},
          'shopping': {'listId': 'groceries'},
        }),
      );
      expect(settings.of(.kanban), isNull);
    });

    test('they read back as they were written, and a broken entry costs only its widget', () {
      final settings = const HomeWidgetSettings()
          .withConfig(.tasks, const HomeWidgetConfig(listId: 'chores'))
          .withConfig(
            .kanban,
            const HomeWidgetConfig(listId: 'household', columnId: 'doing'),
          );

      final read = HomeWidgetSettings.fromJson({
        ...jsonDecode(jsonEncode(settings.toJson())) as Map<String, Object?>,
        'agenda': 'broken',
        'weather': {'city': 'Berlin'},
      });

      expect(read, equals(settings));
    });
  });

  // The native widgets write the app's own addresses into their links
  // (`WidgetPictures.swift`, `HomeScreenWidgets.kt`), and Flutter hands the router the
  // link's path: a route that moves breaks a tap on a widget.
  test('a tap on a widget leads to the address its link names', () {
    String path(String link) => Uri.parse(link).path;

    expect(
      path('hiwiski://widget/calendar'),
      equals(const CalendarRoute().location),
    );
    expect(
      path('hiwiski://widget/tasks/list/abc'),
      equals(const TodoListRoute(listId: 'abc').location),
    );
    final setUp = Uri.parse(
      'hiwiski://widget/account/home-widgets?kind=kanban',
    );
    expect(
      '${setUp.path}?${setUp.query}',
      equals(const HomeWidgetsRoute(kind: 'kanban').location),
    );
  });

  test(
    'a due date goes to the widgets as a date, as the server writes it',
    () async {
      final bridge = _Bridge();
      final summary = listSnapshot(
        list: _list('chores', 'STANDARD'),
        todos: [_todo('bins', 'Bins', dueDate: DateTime(2026, 11, 14))],
        position: 3,
      );

      await HomeWidgetRepository(bridge).publishList(
        .tasks,
        const HomeWidgetConfig(listId: 'chores'),
        summary,
        pending: true,
      );

      final written =
          jsonDecode(bridge.snapshots['tasks']!) as Map<String, dynamic>;
      expect(written['source'], equals('app'));
      expect(written['pending'], isTrue);
      expect(written['config'], equals({'listId': 'chores'}));
      final list = written['list'] as Map<String, dynamic>;
      expect(list['position'], equals(3));
      expect((list['items'] as List).single['dueDate'], equals('2026-11-14'));
    },
  );
}

class _Bridge implements HomeWidgetBridge {
  final snapshots = <String, String?>{};

  @override
  bool get supported => true;

  @override
  Future<void> setSnapshot(String kind, String? json) async =>
      snapshots[kind] = json;

  @override
  Future<void> setConfig(String json) async {}

  @override
  Future<void> setCredentials({String? server, String? token}) async {}

  @override
  Future<void> clear() async => snapshots.clear();
}

Calendar _calendar(String id, String color) => .new(
  id: id,
  ownerId: 'anna',
  version: 1,
  name: id,
  colorToken: color,
  kind: 'LOCAL',
  position: 0,
  tags: '',
);

CalendarEvent _event(
  String id,
  String calendarId, {
  required String title,
  required String timeForm,
  DateTime? startDate,
  DateTime? endDate,
  String? localStart,
  String? localEnd,
  String? rrule,
  Map<String, Object?> exceptions = const {},
}) => .new(
  id: id,
  ownerId: 'anna',
  version: 1,
  calendarId: calendarId,
  title: title,
  timeForm: timeForm,
  startDate: startDate,
  endDate: endDate,
  localStart: localStart,
  localEnd: localEnd,
  timeZone: 'Europe/Berlin',
  rrule: rrule,
  exceptions: jsonEncode(exceptions),
  attendees: '',
  tags: '',
);

TodoList _list(String id, String kind, {List<Map<String, Object?>>? columns}) =>
    .new(
      id: id,
      ownerId: 'anna',
      version: 1,
      name: id,
      kind: kind,
      columns: columns == null ? null : jsonEncode(columns),
      colorToken: 'BLUE',
      position: 0,
      assignees: '',
      tags: '',
    );

Todo _todo(
  String id,
  String title, {
  int position = 0,
  bool done = false,
  bool deleted = false,
  String? columnId,
  double? amount,
  String? unit,
  DateTime? dueDate,
}) => .new(
  id: id,
  ownerId: 'anna',
  version: 1,
  deletedAt: deleted ? DateTime(2026, 11, 1) : null,
  listId: 'list',
  title: title,
  status: done ? 'DONE' : 'OPEN',
  columnId: columnId,
  dueDate: dueDate,
  assignees: '',
  tags: '',
  position: position,
  amount: amount,
  unit: unit,
);
