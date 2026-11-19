import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

/// **A device without a sync position fetches the state, not the history**.
///
/// The log is cleaned up after the retention period. If a fresh device replayed it from
/// 0, it would be missing everything nobody had touched since. In the browser this hits
/// every page load: there the database lives only in memory.
void main() {
  late HiwiskiDatabase db;
  late _FakeServer server;
  late ProviderContainer container;

  const instance = '00000000-0000-0000-0000-00000000000a';
  const anna = 'anna@http://hiwiski.test';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    db = HiwiskiDatabase(NativeDatabase.memory());
    server = _FakeServer();
    final api = HiwiskiApi(tokens: NoTokens(), baseUrl: 'http://hiwiski.test');
    api.dio.httpClientAdapter = server;
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
        hiwiskiApiProvider.overrideWithValue(api),
        sessionFrom(signedInAnna),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  Map<String, dynamic> list(String id, String name, int version) => {
    'seq': version,
    'entityType': 'TODO_LIST',
    'entityId': id,
    'op': 'upsert',
    'version': version,
    'fields': {'name': name},
  };

  Map<String, dynamic> page(
    List<Map<String, dynamic>> changes,
    int latestSeq, {
    String? cursor,
  }) => {
    'changes': changes,
    'latestSeq': latestSeq,
    'hasMore': cursor != null,
    'instanceId': instance,
    'resyncRequired': false,
    'snapshotCursor': ?cursor,
  };

  test(
    'a fresh device pulls the snapshot and then the log from its position',
    () async {
      server.snapshotPages = [
        page([list('l1', 'Shopping', 3)], 42, cursor: '42:TODO_LIST:l1'),
        page([list('l2', 'Garden', 40)], 42),
      ];

      await container.read(syncEngineProvider).syncNow();

      final names = (await db.select(db.todoLists).get()).map(
        (row) => row.name,
      );
      expect(names, containsAll(['Shopping', 'Garden']));

      expect(
        server.pulls.map((body) => body['snapshot'] ?? false),
        equals([true, true, false]),
      );
      // The cursor goes back unchanged, otherwise the snapshot starts over.
      expect(server.pulls[1]['snapshotCursor'], equals('42:TODO_LIST:l1'));
      // Then on with the log — from the position at the start of the snapshot, not from 0.
      expect(server.pulls[2]['lastSeq'], equals(42));
      expect(await db.lastSeq, equals(42));
      expect(await db.snapshotFrom, isNull);
    },
  );

  test(
    "a requested snapshot does not give up the device's own position",
    () async {
      // A device with a position is someone's.
      await db.setOwner(anna);
      await db.setInstanceId(instance);
      await db.setLastSeq(7);
      await db.requestSnapshot();
      server.snapshotPages = [
        page([list('l1', 'Shopping', 3)], 42),
      ];

      await container.read(syncEngineProvider).syncNow();

      // The snapshot was pulled: the request was not ignored. Checking only the last
      // pull, the test passed with no snapshot at all.
      expect(server.pulls.first['snapshot'], isTrue);
      expect(server.snapshotPages, isEmpty);
      expect(
        (await db.select(db.todoLists).get()).map((row) => row.name),
        contains('Shopping'),
      );
      expect(await db.snapshotFrom, isNull);
      // From 7 and not from 42: what was deleted between 7 and 42 is not in the
      // snapshot — only in the log.
      expect(server.pulls.last['snapshot'] ?? false, isFalse);
      expect(server.pulls.last['lastSeq'], equals(7));
    },
  );

  // Someone else adds fifty tasks: every query that watches them runs once for the
  // page, not once per entry — the whole link index hangs off those queries.
  test('a page of the log lands in one go', () async {
    await db.setOwner(anna);
    await db.setInstanceId(instance);
    await db.setLastSeq(7);
    server.logChanges = [
      for (var i = 0; i < 50; i++) list('l$i', 'List $i', 8 + i),
    ];

    int runs = 0;
    final watching = db.select(db.todoLists).watch().listen((_) => runs++);
    await pumpEventQueue();
    final before = runs;

    await container.read(syncEngineProvider).syncNow();
    await pumpEventQueue();
    await watching.cancel();

    expect(await db.select(db.todoLists).get(), hasLength(50));
    expect(await db.lastSeq, equals(57));
    expect(runs - before, equals(1));
  });

  test('the owner is the one the server names, not the reader', () async {
    server.snapshotPages = [
      page([
        {...list('l1', "Ben's list", 3), 'ownerId': 'ben'},
        list('l2', 'Without owner', 4),
      ], 42),
    ];

    await container.read(syncEngineProvider).syncNow();

    final owners = {
      for (final row in await db.select(db.todoLists).get())
        row.id: row.ownerId,
    };
    // Before, every pulled item became Anna's own — and someone else's comment got a
    // delete button. An older server sends no owner; then it stays as it was.
    expect(owners, equals({'l1': 'ben', 'l2': 'anna'}));
  });

  test("the session's confirmation after the first pull keeps what it pulled", () async {
    server.snapshotPages = [
      page([list('l1', 'Shopping', 3)], 42),
    ];

    // A start on a remembered session: the sync runs while the server's
    // confirmation claims the data for the same member — side by side, as on a
    // reload in the browser, whose database starts empty. One after the other, the
    // test passed even without the lock that keeps the two claims apart.
    await Future.wait([
      container.read(syncEngineProvider).syncNow(),
      container.read(sessionStoreProvider).claimLocalData(),
    ]);

    final names = [
      for (final row in await db.select(db.todoLists).get()) row.name,
    ];
    expect(names, equals(['Shopping']));
  });

  test("someone else's data goes before the sync writes", () async {
    await db.setOwner('ben@http://hiwiski.test');
    await db
        .into(db.todoLists)
        .insert(
          TodoListsCompanion.insert(
            id: 'b1',
            ownerId: 'ben',
            name: const Value("Ben's"),
          ),
        );
    server.snapshotPages = [
      page([list('l1', 'Shopping', 3)], 42),
    ];

    await container.read(syncEngineProvider).syncNow();

    final names = [
      for (final row in await db.select(db.todoLists).get()) row.name,
    ];
    expect(names, equals(['Shopping']));
    // Clearing Ben's data cleared the remembered session too; Anna's, who stays, is
    // remembered again — or the next start offline would not open.
    expect(container.read(localSettingsProvider).lastSession, isNotNull);
  });

  // The server was restored while the snapshot ran: page 1 came from the old instance,
  // page 2 from the new one. Discarding the mirror took page 1 with it, so the snapshot
  // starts over instead of going on from page 2's cursor.
  test('a restore noticed on a later snapshot page starts it over', () async {
    const restored = '00000000-0000-0000-0000-00000000000b';
    Map<String, dynamic> on(String instanceId, Map<String, dynamic> page) => {
      ...page,
      'instanceId': instanceId,
    };
    server.snapshotPages = [
      page([list('l1', 'Old first page', 3)], 42, cursor: '42:TODO_LIST:l1'),
      on(restored, page([list('l2', 'New second page', 5)], 9)),
      on(
        restored,
        page([list('l1', 'Shopping', 3)], 9, cursor: '9:TODO_LIST:l1'),
      ),
      on(restored, page([list('l2', 'Garden', 5)], 9)),
    ];
    server.instanceId = restored;

    await container.read(syncEngineProvider).syncNow();

    final names = {
      for (final row in await db.select(db.todoLists).get()) row.name,
    };
    expect(names, equals({'Shopping', 'Garden'}));
    expect(server.pulls[2]['snapshotCursor'], isNull);
  });

  // An older server sends no owner. An item the device already has keeps its owner —
  // it used to become the reader's own on every update.
  test('an update without an owner keeps the stored one', () async {
    server.snapshotPages = [
      page([
        {...list('l1', "Ben's list", 3), 'ownerId': 'ben'},
      ], 42),
    ];
    await container.read(syncEngineProvider).syncNow();
    server.logChanges = [list('l1', "Ben's list, renamed", 43)];

    await container.read(syncEngineProvider).syncNow();

    final row = await db.select(db.todoLists).getSingle();
    expect(row.name, equals("Ben's list, renamed"));
    expect(row.ownerId, equals('ben'));
  });

  test('a device with a position pulls only the log', () async {
    await db.setOwner(anna);
    await db.setInstanceId(instance);
    await db.setLastSeq(7);

    await container.read(syncEngineProvider).syncNow();

    expect(
      server.pulls.map((body) => body['snapshot'] ?? false),
      equals([false]),
    );
  });
}

/// Answers the pull: first the pages of the snapshot, then an empty log.
class _FakeServer implements HttpClientAdapter {
  List<Map<String, dynamic>> snapshotPages = [];
  String instanceId = '00000000-0000-0000-0000-00000000000a';
  List<Map<String, dynamic>> logChanges = [];
  final pulls = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!options.path.endsWith('/api/v1/sync/pull')) {
      return _json({'results': [], 'latestSeq': 0});
    }
    final body = jsonDecode(jsonEncode(options.data)) as Map<String, dynamic>;
    pulls.add(body);
    if (body['snapshot'] == true) {
      return _json(snapshotPages.removeAt(0));
    }
    final changes = logChanges;
    logChanges = [];
    return _json({
      'changes': changes,
      'latestSeq': changes.isEmpty ? body['lastSeq'] : changes.last['seq'],
      'hasMore': false,
      'instanceId': instanceId,
      'resyncRequired': false,
    });
  }

  static ResponseBody _json(Object body) => .fromString(
    jsonEncode(body),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
