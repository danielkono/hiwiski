import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/app/background_sync.dart'
    show BackgroundSync, backgroundSyncProvider;
import 'package:hiwiski/app/background_sync_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

/// **The background sync and the running app never push side by side**.
///
/// The job also fires while the app is alive — on Android the process outlives the
/// screen. Two runs on one outbox would send everything twice and apply every answer
/// twice; so whichever runs second hands over to the other.
void main() {
  test('a background run lets the running app sync instead', () async {
    int synced = 0;
    final app = serveForegroundSync(
      sync: () async => synced++,
      caughtUp: () async {},
    );
    addTearDown(app.close);

    expect(await runBackgroundSync(), isTrue);
    expect(synced, equals(1));
  });

  group('the app', () {
    late HiwiskiDatabase db;
    late _FakeServer server;
    late ProviderContainer container;
    late _Elsewhere elsewhere;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final settings = await LocalSettings.open();
      db = HiwiskiDatabase(NativeDatabase.memory());
      server = _FakeServer();
      elsewhere = _Elsewhere();
      final api = HiwiskiApi(
        tokens: NoTokens(),
        baseUrl: 'http://hiwiski.test',
      );
      api.dio.httpClientAdapter = server;
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          localSettingsProvider.overrideWithValue(settings),
          hiwiskiApiProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(NoTokens()),
          sessionFrom(signedInAnna),
          backgroundSyncProvider.overrideWithValue(elsewhere),
        ],
      );
      await container
          .read(outboxProvider)
          .add(
            entityType: 'TODO_LIST',
            entityId: 'l1',
            op: 'upsert',
            fields: {'name': 'Shopping'},
          );
    });

    tearDown(() {
      container.dispose();
      return db.close();
    });

    test('waits while a background run pushes', () async {
      elsewhere.running = true;

      await container.read(syncEngineProvider).syncNow();

      expect(server.paths, isEmpty);
      expect(await container.read(outboxProvider).pending(), hasLength(1));
    });

    test('pushes itself once the background run is done', () async {
      await container.read(syncEngineProvider).syncNow();

      expect(server.paths, contains('/api/v1/sync/push'));
    });

    test('registers the job for as long as a member is signed in', () async {
      container.listen(backgroundSyncScheduleProvider, (_, _) {});
      await pumpEventQueue();
      expect(elsewhere.signedIn, isTrue);

      // An empty outbox ends nothing: what others changed still has to arrive.
      await container.read(syncEngineProvider).syncNow();
      expect(await container.read(outboxProvider).pending(), isEmpty);
      expect(elsewhere.signedIn, isTrue);

      await container.read(sessionStoreProvider).signedOutElsewhere();
      await pumpEventQueue();
      expect(elsewhere.signedIn, isFalse);
    });
  });
}

class _Elsewhere implements BackgroundSync {
  bool running = false;
  bool? signedIn;

  @override
  Future<void> sessionChanged({required bool signedIn}) async =>
      this.signedIn = signedIn;

  @override
  Future<bool> runningElsewhere() async => running;
}

/// Accepts every push and answers the pull with an empty log.
class _FakeServer implements HttpClientAdapter {
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    final body = jsonDecode(jsonEncode(options.data)) as Map<String, dynamic>?;
    if (options.path.endsWith('/api/v1/sync/push')) {
      return _json({
        'results': [
          for (final mutation in body!['mutations'] as List)
            {
              'mutationId': (mutation as Map)['mutationId'],
              'status': 'applied',
              'version': 1,
            },
        ],
        'latestSeq': 1,
      });
    }
    return _json({
      'changes': [],
      'latestSeq': 0,
      'hasMore': false,
      'instanceId': '00000000-0000-0000-0000-00000000000a',
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
