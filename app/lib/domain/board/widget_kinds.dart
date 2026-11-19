import 'dart:math' as math;

import 'dart:convert';

import '../../core/common/wire.dart';
import '../todo/todo_models.dart';
import 'board_items.dart';

/// The kinds from the widget catalogue.
///
/// **A string, not an enum.** An enum would throw on an unknown value while
/// reading — and that is exactly what must not happen: "An unknown widget type
/// shows a placeholder and **never crashes**. An installed app can be older
/// than the server."
class WidgetKind {
  const WidgetKind._(this.id, {required this.onStartBoard});

  final String id;

  /// "On the start board only **calendar**, **week overview**, **tasks** and **Kanban
  /// board** are available at first."
  final bool onStartBoard;

  static const clock = WidgetKind._('CLOCK', onStartBoard: false);
  static const calendar = WidgetKind._('CALENDAR', onStartBoard: true);

  /// The coming days side by side, events by time and length.
  static const calendarWeek = WidgetKind._('CALENDAR_WEEK', onStartBoard: true);
  static const todoLists = WidgetKind._('TODO_LISTS', onStartBoard: true);
  static const todoList = WidgetKind._('TODO_LIST', onStartBoard: false);

  /// A Kanban board — whole and small, or the cards of one column.
  static const kanbanBoard = WidgetKind._('KANBAN_BOARD', onStartBoard: true);
  static const shoppingList = WidgetKind._(
    'SHOPPING_LIST',
    onStartBoard: false,
  );
  static const recipe = WidgetKind._('RECIPE', onStartBoard: false);
  static const wikiPage = WidgetKind._('WIKI_PAGE', onStartBoard: false);
  static const note = WidgetKind._('NOTE', onStartBoard: false);

  static const all = <WidgetKind>[
    clock,
    calendar,
    calendarWeek,
    todoLists,
    todoList,
    kanbanBoard,
    shoppingList,
    recipe,
    wikiPage,
    note,
  ];

  static const forStartBoard = <WidgetKind>[
    calendar,
    calendarWeek,
    todoLists,
    kanbanBoard,
  ];

  /// `null` if the app does not know this kind — the caller then shows the
  /// placeholder.
  static WidgetKind? tryParse(String id) {
    for (final kind in all) {
      if (kind.id == id) return kind;
    }
    return null;
  }
}

/// The keys in a tile's configuration.
abstract final class WidgetConfigKeys {
  static const startWidth = 'startWidth';

  // Clock.
  static const hour24 = 'hour24';
  static const seconds = 'seconds';
  static const date = 'date';

  // Calendar and week.
  static const calendarIds = 'calendarIds';
  static const days = 'days';
  static const hidePast = 'hidePast';

  // Lists, Kanban, shopping.
  static const listIds = 'listIds';
  static const listId = 'listId';
  static const columnId = 'columnId';
  static const mode = 'mode';
  static const count = 'count';
  static const showDone = 'showDone';

  // Wiki, recipe, note.
  static const pageId = 'pageId';
  static const recipeId = 'recipeId';
  static const text = 'text';
  static const lines = 'lines';
}

/// The `mode` of a Kanban tile.
abstract final class KanbanTileModes {
  static const board = 'BOARD';
  static const column = 'COLUMN';
}

/// The configuration of a tile, read as a map.
///
/// Unknown keys are **preserved**: an older app must not write away the
/// configuration of a newer one when it only changes the position — the same
/// idea as with the fields of a mutation.
class WidgetConfig {
  WidgetConfig(this._values);

  final Map<String, dynamic> _values;

  factory WidgetConfig.decode(String raw) {
    if (raw.trim().isEmpty) return WidgetConfig({});
    try {
      final decoded = jsonDecode(raw);
      return WidgetConfig(decoded is Map<String, dynamic> ? decoded : {});
    } on FormatException {
      // A broken configuration does not cost the board — the tile then shows its
      // placeholder.
      return WidgetConfig({});
    }
  }

  Map<String, dynamic> get values => .unmodifiable(_values);

  String encode() => jsonEncode(_values);

  T? get<T>(String key) {
    final value = _values[key];
    return value is T ? value : null;
  }

  int intOr(String key, int fallback) => (get<num>(key))?.toInt() ?? fallback;

  bool boolOr(String key, bool fallback) => get<bool>(key) ?? fallback;

  List<String> ids(String key) {
    final value = _values[key];
    return value is List ? [for (final entry in value) '$entry'] : const [];
  }

  WidgetConfig with_(String key, Object? value) =>
      .new({..._values, key: ?value});
}

/// A board with its tiles.
class BoardWithWidgets {
  const BoardWithWidgets(this.board, this.widgets);

  final Board board;
  final List<BoardWidget> widgets;

  bool get isGrid => board.layout == BoardLayouts.grid;
}

/// Whether two tiles overlap in the grid.
///
/// **Overlaps are rejected by the board** — a tile underneath another would be
/// invisible, and nobody would know where it went.
bool widgetsOverlap(BoardWidget a, BoardWidget b) =>
    a.gridX < b.gridX + b.gridW &&
    b.gridX < a.gridX + a.gridW &&
    a.gridY < b.gridY + b.gridH &&
    b.gridY < a.gridY + a.gridH;

/// Whether [tile] lies inside a grid of [columns] columns.
bool fitsColumns(BoardWidget tile, int columns) =>
    tile.gridX >= 0 && tile.gridX + tile.gridW <= columns;

/// The first free spot in the grid for a tile of this size — and the width it gets
/// there, at most the grid's.
///
/// Row by row from the top — **gaps are allowed**, they just are not searched for. When
/// nothing above fits, the row below the lowest tile is free.
///
/// It used to fall back to (0, 0) when nothing fit — on a one-column board every time,
/// as new tiles are two wide — and the new tile hid the one there.
({int x, int y, int width}) firstFreeCell(
  List<BoardWidget> existing,
  int columns,
  int width,
  int height,
) {
  final fitting = math.min(width, math.max(1, columns));
  final bottom = existing.fold(
    0,
    (low, tile) => math.max(low, tile.gridY + tile.gridH),
  );
  for (int y = 0; y < bottom; y++) {
    for (int x = 0; x + fitting <= math.max(1, columns); x++) {
      final candidate = _probe(x, y, fitting, height);
      if (!existing.any((other) => widgetsOverlap(candidate, other))) {
        return (x: x, y: y, width: fitting);
      }
    }
  }
  return (x: 0, y: bottom, width: fitting);
}

BoardWidget _probe(int x, int y, int w, int h) => .new(
  id: '',
  ownerId: '',
  version: 0,
  boardId: '',
  kind: '',
  config: '{}',
  gridX: x,
  gridY: y,
  gridW: w,
  gridH: h,
  position: 0,
);

/// How wide a tile is on the start board: one column, two, or the whole row.
///
/// The start board lays its tiles out in columns of at least 320 pixels — enough for a
/// list, too narrow for seven days side by side. Stored in the tile's configuration
/// (`startWidth`), not in `gridW`: that is the wall dashboard's grid, and taking it over
/// would have stretched every existing start tile to two columns.
enum StartWidth {
  normal('NORMAL'),
  wide('WIDE'),
  full('FULL');

  const StartWidth(this.id);

  final String id;

  /// The tile's width — the week overview and a whole board are wide unless set
  /// otherwise.
  static StartWidth of(WidgetConfig config, WidgetKind? kind) {
    final stored = config.get<String>(WidgetConfigKeys.startWidth);
    for (final width in values) {
      if (width.id == stored) return width;
    }
    return switch (kind) {
      .calendarWeek => wide,
      .kanbanBoard when !kanbanOneColumn(config) => wide,
      _ => normal,
    };
  }

  /// The columns it spans among [columns].
  int span(int columns) => switch (this) {
    normal => 1,
    wide => columns < 2 ? 1 : 2,
    full => columns,
  };
}

/// Whether a Kanban tile shows one column instead of the whole board.
bool kanbanOneColumn(WidgetConfig config) =>
    config.get<String>(WidgetConfigKeys.mode) == KanbanTileModes.column;

/// The lists a tasks tile shows.
List<TodoListSummary> selectedLists(
  WidgetConfig config,
  List<TodoListSummary> all,
) {
  if (!config.values.containsKey(WidgetConfigKeys.listIds)) return all;
  final chosen = config.ids(WidgetConfigKeys.listIds).toSet();
  return all.where((summary) => chosen.contains(summary.list.id)).toList();
}
