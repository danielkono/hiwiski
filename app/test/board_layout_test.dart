import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/domain/board/board_items.dart';
import 'package:hiwiski/domain/board/widget_kinds.dart';
import 'package:hiwiski/data/board/board_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where tiles go on the dashboard grid.
void main() {
  late HiwiskiDatabase db;
  late ProviderContainer container;
  late BoardRepository boards;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    db = HiwiskiDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
      ],
    );
    boards = container.read(boardRepositoryProvider);
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  Future<List<BoardWidget>> tiles(Board board) =>
      boards.watchWidgets(board.id).first;

  // Dropping a tile on another moved it onto a spot the other still held: every
  // drop was refused as "occupied".
  test('dropping a tile on another swaps them', () async {
    final board = await boards.ensure('DASHBOARD');
    await boards.addWidget(board: board, kind: 'CLOCK', existing: const []);
    await boards.addWidget(
      board: board,
      kind: 'WEATHER',
      existing: await tiles(board),
    );
    final before = await tiles(board);
    final clock = before.firstWhere((tile) => tile.kind == 'CLOCK');
    final weather = before.firstWhere((tile) => tile.kind == 'WEATHER');

    expect((clock.gridX, clock.gridY), isNot((weather.gridX, weather.gridY)));

    expect(
      await boards.swapWidgets(clock, weather, before, columns: board.columns),
      isTrue,
    );

    final after = await tiles(board);
    final movedClock = after.firstWhere((tile) => tile.id == clock.id);
    final movedWeather = after.firstWhere((tile) => tile.id == weather.id);
    expect((
      movedClock.gridX,
      movedClock.gridY,
    ), equals((weather.gridX, weather.gridY)));
    expect((
      movedWeather.gridX,
      movedWeather.gridY,
    ), equals((clock.gridX, clock.gridY)));
  });

  // A tile past the right edge was cut off and could not be reached to move it back.
  test('a tile is not moved or widened past the grid', () async {
    final board = await boards.ensure('DASHBOARD');
    await boards.addWidget(board: board, kind: 'CLOCK', existing: const []);
    final tile = (await tiles(board)).single;

    expect(
      await boards.moveWidget(
        tile,
        const [],
        board.columns - 1,
        0,
        columns: board.columns,
      ),
      isFalse,
    );
    expect(
      await boards.moveWidget(
        tile,
        const [],
        0,
        0,
        width: board.columns + 1,
        columns: board.columns,
      ),
      isFalse,
    );
  });

  test('fewer columns bring every tile back into the grid', () async {
    Board board = await boards.ensure('DASHBOARD');
    await boards.updateBoard(board, columns: 8);
    board = await boards.ensure('DASHBOARD');
    await boards.addWidget(board: board, kind: 'CLOCK', existing: const []);
    await boards.addWidget(
      board: board,
      kind: 'WEATHER',
      existing: await tiles(board),
    );
    final weather = (await tiles(board)).firstWhere((t) => t.kind == 'WEATHER');
    await boards.moveWidget(weather, await tiles(board), 6, 0, columns: 8);

    await boards.updateBoard(board, columns: 2);

    final after = await tiles(board);
    expect(after.every((tile) => fitsColumns(tile, 2)), isTrue);
    for (final a in after) {
      for (final b in after) {
        if (a.id != b.id) expect(widgetsOverlap(a, b), isFalse);
      }
    }
  });
}
