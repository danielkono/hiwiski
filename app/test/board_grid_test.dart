import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/features/board/view/board_grid.dart';

/// **A board synced with no columns still lays out.** The dashboard divided by its
/// column count unguarded: a 0 gave an endless cell and a broken layout.
void main() {
  testWidgets('zero columns count as one', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: BoardGrid<String>(
              tiles: const ['a', 'b'],
              placeOf: (tile) =>
                  (x: 0, y: tile == 'a' ? 0 : 1, width: 1, height: 1),
              columns: 0,
              tilePadding: .zero,
              stackedGap: 0,
              tileBuilder: Text.new,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text('a')).width, lessThanOrEqualTo(600));
  });
}
