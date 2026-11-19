import 'package:clock/clock.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../core/common/wire.dart';
import '../../../domain/board/widget_kinds.dart';
import '../../../domain/calendar/calendar_items.dart';
import '../../../domain/calendar/occurrence.dart';
import '../../../domain/common/calendar_days.dart';
import '../../../domain/todo/kanban.dart';
import '../../../domain/todo/todo_items.dart';
import '../../../domain/todo/todo_models.dart';
import '../../../domain/wiki/wiki_page.dart';

part 'widget_tile_view_model.g.dart';

// What the tiles of a board show (widget directory). The tiles run on
// the start board, the dashboard and the wall tablet — there over the board's own
// content, not this device's data: the kiosk hands them a container of
// its own.

@riverpod
Stream<List<Calendar>> _calendars(Ref ref) =>
    ref.watch(calendarRepositoryProvider).watchCalendars();

@riverpod
Stream<List<CalendarEvent>> _events(Ref ref) =>
    ref.watch(calendarRepositoryProvider).watchEvents();

@riverpod
Stream<List<TodoListSummary>> _lists(Ref ref) =>
    ref.watch(todoRepositoryProvider).watchLists();

@riverpod
Stream<TodoList?> _list(Ref ref, String listId) =>
    ref.watch(todoRepositoryProvider).watchList(listId);

@riverpod
Stream<List<Todo>> _todos(Ref ref, String listId) =>
    ref.watch(todoRepositoryProvider).watchTodos(listId);

@riverpod
Stream<List<WikiPage>> _pages(Ref ref) =>
    ref.watch(wikiRepositoryProvider).watchPages();

/// A calendar tile: the agenda of the next days, or the week side by side.
@immutable
class const CalendarTileState({
  required final Map<String, Calendar> calendars,

  /// In the tile's window, through the chosen calendars, in order.
  required final List<Occurrence> occurrences,

  /// The days the week shows, from today on.
  required final List<DateTime> days,
});

@riverpod
class CalendarTileViewModel extends _$CalendarTileViewModel {
  /// [week]: the days side by side, from today on; otherwise the agenda, without
  /// what is over when [WidgetConfigKeys.hidePast] says so.
  @override
  Future<CalendarTileState> build(String config, {required bool week}) async {
    final settings = WidgetConfig.decode(config);
    final count = settings.intOr(WidgetConfigKeys.days, week ? 7 : 3);
    final chosen = settings.ids(WidgetConfigKeys.calendarIds).toSet();
    final now = clock.now();
    final today = startOfDay(now);
    final from = !week && settings.boolOr(WidgetConfigKeys.hidePast, false)
        ? now
        : today;
    final to = addDays(today, count);
    const expander = EventExpander();
    final calendars = ref.watch(_calendarsProvider.future);
    final events = ref.watch(_eventsProvider.future);
    return CalendarTileState(
      calendars: {
        for (final calendar in await calendars) calendar.id: calendar,
      },
      occurrences: <Occurrence>[
        for (final event in await events)
          if (chosen.isEmpty || chosen.contains(event.calendarId))
            ...expander.expand(event, from, to),
      ]..sort(),
      days: [for (var i = 0; i < count; i++) addDays(today, i)],
    );
  }
}

/// The lists a tasks tile shows — and, when it is one, its entries.
@immutable
class const ListsTileState({
  required final List<TodoListSummary> lists,

  /// Whether the family has lists at all — "nothing to show" is not "none chosen".
  required final bool anyList,

  /// **A single list shows its entries**, not just its status: whoever puts a single
  /// list on the start board wants to check things off without opening it.
  final List<Todo> todos = const [],
});

@riverpod
class ListsTileViewModel extends _$ListsTileViewModel {
  @override
  Future<ListsTileState> build(String config) async {
    final all = await ref.watch(_listsProvider.future);
    final lists = selectedLists(WidgetConfig.decode(config), all);
    return ListsTileState(
      lists: lists,
      anyList: all.isNotEmpty,
      todos: lists.length == 1
          ? await ref.watch(_todosProvider(lists.single.list.id).future)
          : const [],
    );
  }

  /// The tick itself is saved right away.
  Future<void> setStatus(Todo todo, bool done) =>
      ref.read(todoRepositoryProvider).setStatus(todo, done);
}

/// One list on a tile: its entries, or its board.
@immutable
class ListTileState {
  const ListTileState({required this.list, required this.todos});

  final TodoList list;
  final List<Todo> todos;

  /// An archived list stays on the board as a line, not as boxes nobody may tick.
  bool get archived => list.archivedAt != null;

  List<KanbanColumn> get columns => parseColumns(list.columns);

  Map<String, List<Todo>> get cards => arrangeCards(todos, columns);
}

@riverpod
class ListTileViewModel extends _$ListTileViewModel {
  /// `null` once the list is gone.
  @override
  Future<ListTileState?> build(String listId) async {
    final list = ref.watch(_listProvider(listId).future);
    final todos = ref.watch(_todosProvider(listId).future);
    final row = await list;
    if (row == null) return null;
    return ListTileState(list: row, todos: await todos);
  }
}

/// A page on a tile — and the recipes "recipe of the day" picks from.
@riverpod
class PageTileViewModel extends _$PageTileViewModel {
  /// `null` once the page is gone.
  @override
  Future<WikiPage?> build(String pageId) async =>
      (await ref.watch(_pagesProvider.future))
          .where((page) => page.id == pageId)
          .firstOrNull;
}

@riverpod
class RecipeTileViewModel extends _$RecipeTileViewModel {
  /// The chosen recipe — or, without one, "recipe of the day": the same day yields
  /// the same recipe, otherwise it would change on every repaint and the wall tablet
  /// would flicker. `null` when there is no recipe.
  @override
  Future<WikiPage?> build(String config) async {
    final recipes = [
      for (final page in await ref.watch(_pagesProvider.future))
        if (page.archivedAt == null && page.kind == PageKinds.recipe) page,
    ];
    if (recipes.isEmpty) return null;
    final fixed = WidgetConfig.decode(config)
        .get<String>(WidgetConfigKeys.recipeId);
    return fixed == null
        ? recipes[startOfDay(clock.now()).day % recipes.length]
        : recipes.where((page) => page.id == fixed).firstOrNull ??
              recipes.first;
  }
}

/// What the footer of a tile names: the calendars, the lists, the board.
@immutable
class const TileSummaryState({
  /// The chosen calendars by name — all of them when none is chosen.
  final List<String> calendars = const [],
  final int lists = 0,
  final String? board,

  /// The column, when the tile shows only one.
  final String? column,
});

@riverpod
class TileSummaryViewModel extends _$TileSummaryViewModel {
  @override
  Future<TileSummaryState> build(String kind, String config) async {
    final settings = WidgetConfig.decode(config);
    switch (WidgetKind.tryParse(kind)) {
      case .calendar || .calendarWeek:
        final chosen = settings.ids(WidgetConfigKeys.calendarIds).toSet();
        final calendars = await ref.watch(_calendarsProvider.future);
        return TileSummaryState(
          calendars: [
            for (final calendar in calendars)
              if (chosen.isEmpty || chosen.contains(calendar.id)) calendar.name,
          ],
        );
      case .todoLists:
        return TileSummaryState(
          lists: selectedLists(
            settings,
            await ref.watch(_listsProvider.future),
          ).length,
        );
      case .kanbanBoard:
        final listId = settings.get<String>(WidgetConfigKeys.listId);
        final board = listId == null
            ? null
            : await ref.watch(_listProvider(listId).future);
        if (board == null) return const TileSummaryState();
        final column = parseColumns(board.columns)
            .where(
              (c) => c.id == settings.get<String>(WidgetConfigKeys.columnId),
            )
            .firstOrNull;
        return TileSummaryState(
          board: board.name,
          column: kanbanOneColumn(settings) ? column?.name : null,
        );
      default:
        return const TileSummaryState();
    }
  }
}
