import '../../core/api/generated/export.dart';
import '../../core/common/wire.dart';
import '../calendar/calendar_items.dart';
import '../calendar/occurrence.dart';
import '../common/calendar_days.dart';
import '../todo/kanban.dart';
import '../todo/todo_items.dart';

/// What the home screen widgets show, made from this device's data.
///
/// **The same answer the server gives** (`getAgenda`, `getListSummary`), in the same
/// generated types: the widget keeps whichever of the two pictures is newer, and both
/// must read alike. The server expands events by the same rules
/// (`golden/occurrences.json`) and derives a card's column the same way.

/// The most an agenda carries — the server's default limit.
const agendaLimit = 50;

/// The most entries a list carries — the server's default limit.
const listLimit = 30;

/// The coming occurrences of the chosen calendars, from [now] to the end of the last of
/// [days] days. [calendarIds] empty: every calendar.
Agenda agendaSnapshot({
  required List<CalendarEvent> events,
  required List<Calendar> calendars,
  required List<String> calendarIds,
  required int days,
  required DateTime now,
  required String timeZone,
  required int position,
  int limit = agendaLimit,
}) {
  final from = DateTime(now.year, now.month, now.day, now.hour, now.minute);
  final to = addDays(startOfDay(now), days);
  final chosen = calendarIds.toSet();
  final colors = {
    for (final calendar in calendars) calendar.id: calendar.colorToken,
  };
  const expander = EventExpander();
  final occurrences = <Occurrence>[
    for (final event in events)
      if (chosen.isEmpty || chosen.contains(event.calendarId))
        ...expander.expand(event, from, to),
  ]..sort();
  return Agenda(
    position: position,
    timeZone: timeZone,
    from: localStamp(from),
    to: localStamp(to),
    occurrences: [
      for (final occurrence in occurrences.take(limit))
        AgendaOccurrence(
          eventId: occurrence.event.id,
          calendarId: occurrence.event.calendarId,
          title: occurrence.event.title,
          location: occurrence.event.location,
          colorToken: colors[occurrence.event.calendarId],
          start: localStamp(occurrence.start),
          end: localStamp(occurrence.end),
          allDay: occurrence.allDay,
          moved: occurrence.moved,
        ),
    ],
    truncated: occurrences.length > limit,
  );
}

/// A list's open entries in its order and its counts — or, with [columnId] on a Kanban
/// board, the cards standing in that column. A column the board no longer has counts
/// as none.
ListSummary listSnapshot({
  required TodoList list,
  required List<Todo> todos,
  required int position,
  String? columnId,
  int limit = listLimit,
}) {
  final live = [
    for (final todo in todos)
      if (todo.deletedAt == null) todo,
  ]..sort(_inListOrder);
  final done = live.where((todo) => todo.status == TodoStatuses.done).length;
  final columns = list.kind == kindKanban
      ? parseColumns(list.columns)
      : const <KanbanColumn>[];
  final column = columns.where((c) => c.id == columnId).firstOrNull;
  final shown = [
    for (final todo in live)
      if (column == null
          ? todo.status != TodoStatuses.done
          : columnOf(todo, columns) == column.id)
        todo,
  ];
  return ListSummary(
    position: position,
    listId: list.id,
    name: list.name,
    kind: list.kind,
    colorToken: list.colorToken,
    archived: list.archivedAt != null,
    openCount: live.length - done,
    doneCount: done,
    column: column == null
        ? null
        : ListSummaryColumn(
            id: column.id,
            name: column.name,
            colorToken: column.colorToken,
            done: column.done,
            count: shown.length,
          ),
    items: [
      for (final todo in shown.take(limit))
        ListSummaryItem(
          todoId: todo.id,
          title: todo.title,
          done: todo.status == TodoStatuses.done,
          amount: todo.amount,
          unit: todo.unit,
          dueDate: todo.dueDate,
          dueTime: todo.dueTime,
        ),
    ],
    truncated: shown.length > limit,
  );
}

/// Position, then title — the order of the list in the app.
int _inListOrder(Todo a, Todo b) {
  final byPosition = a.position.compareTo(b.position);
  return byPosition != 0 ? byPosition : a.title.compareTo(b.title);
}
