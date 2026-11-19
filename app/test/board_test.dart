import 'package:hiwiski/domain/board/widget_kinds.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/board/board_items.dart';

/// The acceptance case for boards, as far as it can be computed:
///
/// * "**A widget type the app does not know shows a placeholder.**"
/// * "Gaps are allowed, **the board rejects overlaps** — a tile underneath another one
///   would be invisible, and nobody would know where it went."
void main() {
  BoardWidget tile(int x, int y, {int w = 1, int h = 1, String id = 't'}) =>
      .new(
        id: id,
        ownerId: 'anna',
        version: 1,
        boardId: 'b',
        kind: 'CLOCK',
        config: '{}',
        gridX: x,
        gridY: y,
        gridW: w,
        gridH: h,
        position: 0,
      );

  group('unknown kinds', () {
    test('a kind the app does not know yields null instead of an error', () {
      // An installed app can be **older** than the server. An enum
      // would throw here — that is why the kind is a string and resolving it is a
      // `tryParse`.
      expect(WidgetKind.tryParse('WEATHER_STATION_2031'), isNull);
      expect(WidgetKind.tryParse(''), isNull);
    });

    test('the known kinds resolve', () {
      for (final kind in WidgetKind.all) {
        expect(WidgetKind.tryParse(kind.id), same(kind));
      }
    });

    test(
      'the start board initially offers calendar, week, tasks and boards',
      () {
        // Only calendar, week overview, tasks and Kanban board.
        expect(
          WidgetKind.forStartBoard,
          equals([
            WidgetKind.calendar,
            WidgetKind.calendarWeek,
            WidgetKind.todoLists,
            WidgetKind.kanbanBoard,
          ]),
        );
        expect(WidgetKind.calendar.onStartBoard, isTrue);
        expect(WidgetKind.clock.onStartBoard, isFalse);
      },
    );
  });

  group('configuration', () {
    test('unknown keys are preserved', () {
      // An older app must not overwrite a newer one's configuration when it only changes
      // the position — the same idea as with the fields of a mutation.
      final config = WidgetConfig.decode(
        '{"seconds":true,"from_the_future":42}',
      );
      final changed = config.with_('seconds', false);

      expect(changed.values['from_the_future'], equals(42));
      expect(changed.boolOr('seconds', true), isFalse);
    });

    test('a broken configuration does not cost the board', () {
      expect(WidgetConfig.decode('not JSON').values, isEmpty);
      expect(WidgetConfig.decode('').values, isEmpty);
      expect(WidgetConfig.decode('[1,2,3]').values, isEmpty);
    });

    test('defaults apply where nothing is set', () {
      final empty = WidgetConfig.decode('{}');
      expect(empty.intOr('days', 3), equals(3));
      expect(empty.boolOr('hidePast', true), isTrue);
      expect(empty.ids('calendarIds'), isEmpty);
    });
  });

  group('grid', () {
    test('two tiles side by side do not overlap', () {
      expect(widgetsOverlap(tile(0, 0, w: 2), tile(2, 0, w: 2)), isFalse);
    });

    test('two tiles stacked vertically do not overlap', () {
      expect(widgetsOverlap(tile(0, 0, h: 1), tile(0, 1, h: 1)), isFalse);
    });

    test('a tile on top of another one overlaps', () {
      // Exactly the case the board rejects: it would be invisible, and nobody would know
      // where it went.
      expect(widgetsOverlap(tile(0, 0, w: 2, h: 2), tile(1, 1)), isTrue);
    });

    test('gaps are allowed', () {
      // Free space is searched row by row, but not enforced.
      final occupied = [tile(0, 0, w: 2, h: 2, id: 'a')];
      expect(firstFreeCell(occupied, 4, 2, 2), equals((x: 2, y: 0, width: 2)));
    });

    test('the second row when the first one is full', () {
      final occupied = [
        tile(0, 0, w: 2, h: 1, id: 'a'),
        tile(2, 0, w: 2, h: 1, id: 'b'),
      ];
      expect(firstFreeCell(occupied, 4, 2, 1), equals((x: 0, y: 1, width: 2)));
    });

    // A tile wider than the board used to land at (0, 0) — on a one-column board
    // every new tile did, hiding the one there.
    test('a tile wider than the board is made to fit', () {
      expect(firstFreeCell(const [], 2, 4, 1), equals((x: 0, y: 0, width: 2)));
      final occupied = [tile(0, 0, w: 1, h: 2, id: 'a')];
      expect(firstFreeCell(occupied, 1, 2, 2), equals((x: 0, y: 2, width: 1)));
    });
  });
}
