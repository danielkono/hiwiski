import 'package:drift/native.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/domain/board/board_items.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/core/sync/sync_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hiwiski/features/board/start/start_view_model.dart';
import 'package:hiwiski/app/repositories.dart';

/// **Exactly one start board and exactly one dashboard per member**.
///
/// When testing the fresh instance, the app created **two** start boards: the provider
/// above it reruns as soon as the stream of existing boards emits for the first time —
/// and at that point the first call had not finished yet. Both saw no board and created
/// one. The server rejected the second one (`board_one_per_kind`), the mutation got
/// stuck in the outbox, and the user saw "Change could not be applied" on the **next
/// task** they created — in a place, that is, that had nothing to do with the cause.
void main() {
  late HiwiskiDatabase db;
  late ProviderContainer container;

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
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  test('two concurrent calls create one board, not two', () async {
    final repository = container.read(boardRepositoryProvider);

    // Exactly the race: two calls before the first one has written.
    final results = await Future.wait([
      repository.ensure('START'),
      repository.ensure('START'),
    ]);

    expect(results.first.id, equals(results.last.id));
    expect(await db.select(db.boards).get(), hasLength(1));
    // And exactly one mutation in the outbox — not two, one of which is rejected
    // forever.
    expect(await db.select(db.outboxEntries).get(), hasLength(1));
  });

  test('a second call afterwards finds the same board', () async {
    final repository = container.read(boardRepositoryProvider);

    final first = await repository.ensure('START');
    final second = await repository.ensure('START');

    expect(second.id, equals(first.id));
    expect(await db.select(db.boards).get(), hasLength(1));
  });

  test('start and dashboard are two different boards', () async {
    final repository = container.read(boardRepositoryProvider);

    final start = await repository.ensure('START');
    final dashboard = await repository.ensure('DASHBOARD');

    expect(start.id, isNot(dashboard.id));
    expect(start.layout, equals('FLOW'));
    expect(dashboard.layout, equals('GRID'));
    // Only the dashboard gets an address.
    expect(start.token, isNull);
    expect(dashboard.token, isNotNull);
  });

  group('new device', () {
    // The phone opening the page for the first time: empty database, not synced yet.
    // A board created here collides with the one the computer already has.
    Future<ProviderContainer> newDevice(
      SyncStatus status, {
      int lastSeq = 0,
    }) async {
      final settings = await LocalSettings.open();
      await db.setLastSeq(lastSeq);
      final device = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          localSettingsProvider.overrideWithValue(settings),
          syncStatusProvider.overrideWithValue(status),
        ],
      );
      addTearDown(device.dispose);
      return device;
    }

    // Without a listener Riverpod pauses the provider — and `.future` would never return.
    Future<Board> start(ProviderContainer device) async {
      final sub = device.listen(startViewModelProvider, (_, _) {});
      addTearDown(sub.close);
      return (await device.read(startViewModelProvider.future)).board;
    }

    test('creates no board before the first sync', () async {
      final device = await newDevice(const SyncStatus());
      final board = start(device);
      // Every pending step runs to its end — the existing boards delivered, and still
      // no board. Not a fixed pause, which a board created slowly would have passed.
      await pumpEventQueue(times: 200);

      expect(device.read(startViewModelProvider).isLoading, isTrue);
      // Left open on purpose: the test is about what happens meanwhile.
      board.ignore();
      expect(await db.select(db.boards).get(), isEmpty);
      expect(await db.select(db.outboxEntries).get(), isEmpty);
    });

    test('creates one if a pull has happened before', () async {
      final device = await newDevice(const SyncStatus(), lastSeq: 7);

      final board = await start(device);

      expect(board.kind, equals('START'));
      expect(await db.select(db.boards).get(), hasLength(1));
    });

    test('creates one once the sync in this session has finished', () async {
      final device = await newDevice(SyncStatus(lastSyncedAt: DateTime(2026)));

      final board = await start(device);

      expect(board.kind, equals('START'));
    });

    // The first sync reached the server and failed: waiting for a pull that does not
    // come kept the start screen loading for good.
    test('creates one when the first sync failed', () async {
      final device = await newDevice(const SyncStatus(lastAttemptFailed: true));

      final board = await start(device);

      expect(board.kind, equals('START'));
    });

    test('creates one offline anyway', () async {
      final device = await newDevice(const SyncStatus(online: false));

      final board = await start(device);

      expect(board.kind, equals('START'));
    });
  });
}
