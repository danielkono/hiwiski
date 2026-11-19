import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../domain/board/widget_kinds.dart';

/// The name of a tile kind — in the add menu, on the start screen and on a tile.
String widgetKindLabel(L l, WidgetKind kind) => switch (kind) {
  .clock => l.widgetClock,
  .calendar => l.widgetCalendar,
  .calendarWeek => l.widgetCalendarWeek,
  .todoLists => l.widgetTodoLists,
  .todoList => l.widgetTodoList,
  .kanbanBoard => l.widgetKanban,
  .shoppingList => l.widgetShoppingList,
  .recipe => l.widgetRecipe,
  .wikiPage => l.widgetWikiPage,
  _ => l.widgetNote,
};

/// Where a tile sits on the grid, in cells.
typedef GridPlace = ({int x, int y, int width, int height});

/// The tiles of a board on its grid — for the dashboard and the kiosk alike.
///
/// Each tile at its cells; where a cell would be narrower than [minCellWidth], below
/// each other in reading order instead. A board with no columns counts as one: the
/// dashboard divided by its column count unguarded, and a synced 0 gave an endless
/// cell. The two copies had already drifted apart on exactly that.
class BoardGrid<T> extends StatelessWidget {
  const BoardGrid({
    super.key,
    required this.tiles,
    required this.placeOf,
    required this.columns,
    required this.tileBuilder,
    required this.tilePadding,
    required this.stackedGap,
    this.stackedPadding = EdgeInsets.zero,
    this.scrolls = false,
  });

  final List<T> tiles;
  final GridPlace Function(T tile) placeOf;
  final int columns;
  final Widget Function(T tile) tileBuilder;

  /// Around each tile on the grid.
  final EdgeInsets tilePadding;

  /// Between tiles below each other.
  final double stackedGap;
  final EdgeInsets stackedPadding;

  /// Whether the grid scrolls itself — the kiosk fills the screen; the dashboard sits
  /// in a page that scrolls.
  final bool scrolls;

  static const minCellWidth = HiwiskiMetrics.boardMinCell;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cell = constraints.maxWidth / (columns < 1 ? 1 : columns);

      if (cell < minCellWidth) {
        final stacked = [
          for (final tile in tiles)
            Padding(
              padding: .only(bottom: stackedGap),
              child: tileBuilder(tile),
            ),
        ];
        return scrolls
            ? ListView(padding: stackedPadding, children: stacked)
            : Padding(
                padding: stackedPadding,
                child: Column(children: stacked),
              );
      }

      final rows = tiles.fold<int>(1, (max, tile) {
        final place = placeOf(tile);
        return place.y + place.height > max ? place.y + place.height : max;
      });
      final grid = SizedBox(
        height: rows * cell,
        child: Stack(
          children: [
            for (final tile in tiles)
              if (placeOf(tile) case final place)
                Positioned(
                  left: place.x * cell,
                  top: place.y * cell,
                  width: place.width * cell,
                  height: place.height * cell,
                  child: Padding(
                    padding: tilePadding,
                    child: tileBuilder(tile),
                  ),
                ),
          ],
        ),
      );
      return scrolls ? SingleChildScrollView(child: grid) : grid;
    },
  );
}
