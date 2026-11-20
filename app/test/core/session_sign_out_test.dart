import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show AsyncCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/background_sync.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/api/hiwiski_failure.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/sync/entity_codec.dart';
import 'package:hiwiski/domain/common/server_address.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/storage/token_store.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

/// **Signing out clears the device — after the last sync, not during it.** And the
/// sync's own ways out: a dead token signs out, an unreachable server keeps the outbox.
///
/// `syncNow()` returned at once while a run was in progress. A sign-out took that for
/// "synced", wiped the outbox with a change that was never pushed, and the run still
/// under way wrote the departed member's rows back into the cleared database.
void main() {
  late HiwiskiDatabase db;
  late _FakeServer server;
  late _Tokens tokens;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    db = HiwiskiDatabase(NativeDatabase.memory());
    server = _FakeServer();
    tokens = _Tokens();
    final api = HiwiskiApi(tokens: tokens, baseUrl: 'http://hiwiski.test');
    api.dio.httpClientAdapter = server;
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
        tokenStoreProvider.overrideWithValue(tokens),
        hiwiskiApiProvider.overrideWithValue(api),
        sessionFrom(_signedIn),
      ],
    );
    // The session lives as long as the app does; without a listener the container
    // would drop it between two reads.
    container.listen(sessionProvider, (_, _) {});
    // A device that has synced before: it pulls only the log.
    await db.setOwner('anna@http://hiwiski.test');
    await db.setInstanceId(_instance);
    await db.setLastSeq(7);
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  Future<void> edit(String name) => container
      .read(outboxProvider)
      .add(
        entityType: 'TODO_LIST',
        entityId: 'l1',
        op: 'upsert',
        fields: {'name': name},
      );

  test('sign-out pushes what was edited during a running sync', () async {
    final engine = container.read(syncEngineProvider);
    final release = server.holdPull = Completer();
    final running = engine.syncNow();
    await server.pullStarted.future;

    // Edited while the run pulls — and then signed out right away.
    await edit('Shopping');
    final signingOut = container.read(sessionStoreProvider).signOut();
    release.complete();
    await running;
    await signingOut;

    expect(
      server.pushed,
      contains('Shopping'),
      reason: 'the change went out before the device was cleared',
    );
    expect(server.loggedOutAfterPush, isTrue);
    expect(await db.select(db.outboxEntries).get(), isEmpty);
    expect(tokens.token, isNull);
  });

  // Away from home, the home server does not answer: the logout used to come first,
  // and the device stayed signed in on the start screen until it timed out.
  test('a server that does not answer does not hold the sign-out up', () async {
    await db
        .into(db.todoLists)
        .insert(TodoListsCompanion.insert(id: 'l1', ownerId: 'anna'));
    final release = server.holdLogout = Completer();

    final signingOut = container.read(sessionStoreProvider).signOut();
    await server.logoutStarted.future;

    expect(
      container.read(sessionProvider).stage,
      equals(SessionStage.signedOut),
    );
    expect(tokens.token, isNull);
    expect(await db.select(db.todoLists).get(), isEmpty);
    expect(server.pulls, isZero, reason: 'nothing waited to go out');

    // Whoever signs in meanwhile keeps their token: the logout goes out in the name
    // of the one it drops, and nothing is cleared after it.
    tokens.token = 'next';
    release.complete();
    await signingOut;
    expect(server.logoutAuthorization, equals('Bearer token'));
    expect(tokens.token, equals('next'));
  });

  test('the last sync asks the server nothing when nothing waits', () async {
    server.offline = true;

    await container.read(syncEngineProvider).syncLast();

    expect(server.authorizationsTo('hiwiski.test'), isEmpty);
  });

  // The sign-in shows as soon as the session ends, while a run still under way is
  // waited for: clearing the device after the next member is in took their data.
  test('signing in waits until the sign-out has cleared the device', () async {
    final engine = container.read(syncEngineProvider);
    final release = server.holdPull = Completer();
    final running = engine.syncNow();
    await server.pullStarted.future;
    final store = container.read(sessionStoreProvider);
    final ended = Completer<void>();
    final listening = container.listen(sessionProvider, (_, next) {
      if (next.stage == .signedOut && !ended.isCompleted) ended.complete();
    });
    addTearDown(listening.close);
    String? ownerAtRedeem = 'not asked';
    server.onRedeem = () async => ownerAtRedeem = await db.owner;

    final signingOut = store.signOut();
    await ended.future;
    final redeeming = store
        .redeemInvitation(
          'code',
          const RedeemInvitationRequest(
            displayName: 'Ben',
            username: 'ben',
            password: 'secret',
            device: DeviceRegistration(deviceName: 'Phone', platform: .ios),
          ),
        )
        .onError<Object>((_, _) {});
    await pumpEventQueue();
    expect(server.redeems, isZero, reason: 'the run is still under way');

    release.complete();
    await running;
    await signingOut;
    await redeeming;

    expect(server.redeems, equals(1));
    expect(ownerAtRedeem, isNull, reason: 'the device was cleared before');
  });

  test('nothing a run receives after a sign-out is written', () async {
    // Cleared at once, as a lost phone would be (Account → Customize).
    await container.read(localSettingsProvider).setWipeOnAccessLost(true);
    final engine = container.read(syncEngineProvider);
    final release = server.holdPull = Completer();
    server.pullAnswer = [_list('b1', "Anna's secret list")];
    final running = engine.syncNow().onError<Object>((_, _) {});
    await server.pullStarted.future;

    // Signed out elsewhere while the pull is still on its way.
    final signingOut = container
        .read(sessionStoreProvider)
        .signedOutElsewhere();
    release.complete();
    await running;
    await signingOut;

    expect(await db.select(db.todoLists).get(), isEmpty);
    expect(await db.lastSeq, equals(0));
    expect(await db.owner, isNull);
  });

  test(
    'forgetting the server logs out and clears after a running sync',
    () async {
      final engine = container.read(syncEngineProvider);
      final release = server.holdPull = Completer();
      server.pullAnswer = [_list('b1', "Anna's secret list")];
      final running = engine.syncNow().onError<Object>((_, _) {});
      await server.pullStarted.future;

      final forgetting = container.read(sessionStoreProvider).forgetServer();
      release.complete();
      await running;
      await forgetting;

      expect(server.loggedOut, isTrue);
      expect(await db.select(db.todoLists).get(), isEmpty);
      expect(await db.owner, isNull);
      expect(tokens.token, isNull);
    },
  );

  // Account → Customize: "Delete everything at once".
  test('a 401 during a sync clears the device if chosen so', () async {
    await container.read(localSettingsProvider).setWipeOnAccessLost(true);
    await edit('Shopping');
    server.unauthorized = true;

    await container.read(syncEngineProvider).syncNow();

    expect(
      container.read(sessionProvider).stage,
      equals(SessionStage.signedOut),
    );
    expect(tokens.token, isNull);
    expect(await db.select(db.outboxEntries).get(), isEmpty);
    expect(await db.owner, isNull);
  });

  // The default: locked, not cleared — the change made meanwhile waits for the
  // same member to sign in again, and nothing syncs until then.
  test('a 401 during a sync locks the device and keeps its changes', () async {
    await edit('Shopping');
    server.unauthorized = true;

    await container.read(syncEngineProvider).syncNow();

    expect(
      container.read(sessionProvider).stage,
      equals(SessionStage.accessLost),
    );
    expect(container.read(sessionProvider).member?.username, equals('anna'));
    expect(tokens.token, isNull);
    expect(await db.select(db.outboxEntries).get(), hasLength(1));
    expect(await db.owner, isNotNull);

    // Locked, the sync does not run: no token, and nobody to run it for.
    server.unauthorized = false;
    await container.read(syncEngineProvider).syncNow();
    expect(server.pushed, isEmpty);
  });

  test('offline, the sync keeps the outbox and says so', () async {
    await edit('Shopping');
    server.offline = true;
    final engine = container.read(syncEngineProvider);

    await engine.syncNow();

    expect(engine.state.online, isFalse);
    expect(await db.select(db.outboxEntries).get(), hasLength(1));
    expect(
      container.read(sessionProvider).stage,
      equals(SessionStage.signedIn),
    );

    // Back online, the next run pushes it.
    server.offline = false;
    await engine.syncNow();
    expect(engine.state.online, isTrue);
    expect(server.pushed, equals(['Shopping']));
    expect(await db.select(db.outboxEntries).get(), isEmpty);
  });

  // The background isolate claims with its own lock: when the owner changes under a
  // pull, the pages before that claim were cleared while the position says they are
  // here — a snapshot has to fetch them.
  test('an owner that changes under a pull asks for a snapshot', () async {
    final engine = container.read(syncEngineProvider);
    final release = server.holdPull = Completer();
    final running = engine.syncNow();
    await server.pullStarted.future;

    await db.setOwner('anna@elsewhere');
    release.complete();
    await running;

    expect(await db.snapshotFrom, isNotNull);
  });

  test('connecting to another server forgets the previous one first', () async {
    await db
        .into(db.todoLists)
        .insert(TodoListsCompanion.insert(id: 'l1', ownerId: 'anna'));

    await container
        .read(sessionStoreProvider)
        .connect(ServerAddress.parse('http://other.test')!)
        .onError<Object>(
          (_, _) => const Handshake(
            apiVersion: 'v1',
            serverVersion: 'x',
            minClientVersion: '0',
            setupCompleted: true,
            cleartext: true,
          ),
        );

    expect(server.loggedOut, isTrue);
    expect(tokens.token, isNull);
    expect(await db.select(db.todoLists).get(), isEmpty);
    expect(server.authorizationsTo('other.test'), everyElement(isNull));
  });

  test(
    'a server error schedules a retry, a refused request does not',
    () async {
      final engine = container.read(syncEngineProvider);

      server.failWith = 503;
      await expectLater(engine.syncNow(), throwsA(isA<HiwiskiFailure>()));
      expect(engine.retryScheduled, isTrue);

      await engine.stop();
      server.failWith = 400;
      await expectLater(engine.syncNow(), throwsA(isA<HiwiskiFailure>()));
      expect(engine.retryScheduled, isFalse);
    },
  );

  /// Another device restores a backup: a refused change is no failure here, but the
  /// news that the app waits — and its changes stay until the restore is done.
  test('a change refused during a restore makes the app wait', () async {
    final engine = container.read(syncEngineProvider);
    server
      ..failWith = 503
      ..failCode = 'instance.restoring';

    await engine.syncNow();

    expect(container.read(sessionProvider).restoring, isTrue);
    expect(engine.retryScheduled, isTrue);
    expect(engine.state.lastAttemptFailed, isFalse);
    await engine.stop();
  });

  /// The server lost, restored from an older backup: what this device saw since is
  /// kept aside instead of thrown away with the mirror.
  test('a restore keeps aside what the server no longer has', () async {
    final engine = container.read(syncEngineProvider);
    await const TodoListCodec().upsert(
      db,
      id: 'l1',
      ownerId: 'anna',
      version: 3,
      containerId: null,
      entityKey: null,
      fields: {'name': 'Wocheneinkauf'},
    );
    await const TodoCodec().upsert(
      db,
      id: 't1',
      ownerId: 'anna',
      version: 5,
      containerId: 'l1',
      entityKey: null,
      fields: {'title': 'Obst', 'status': 'DONE'},
    );
    server
      ..restoredTo = '00000000-0000-0000-0000-00000000000b'
      ..restoredState = [
        {
          'seq': 3,
          'op': 'upsert',
          'entityType': 'TODO_LIST',
          'entityId': 'l1',
          'version': 3,
          'ownerId': 'anna',
          'fields': {'name': 'Wocheneinkauf'},
        },
      ];

    await engine.syncNow();

    final kept = await engine.leftBehind.watch().first;
    expect([for (final row in kept) row.entityId], equals(['t1']));
    expect(
      await db.select(db.todos).get(),
      isEmpty,
      reason: 'the mirror is the server',
    );
  });

  test('the retry waits longer each time, up to a minute', () async {
    final engine = container.read(syncEngineProvider);
    server.offline = true;
    final waits = <Duration>[];
    for (int i = 0; i < 5; i++) {
      waits.add(engine.nextRetry);
      await engine.syncNow();
    }
    expect(waits.map((wait) => wait.inSeconds), equals([15, 30, 60, 60, 60]));

    server.offline = false;
    await engine.syncNow();
    expect(engine.nextRetry, equals(const Duration(seconds: 15)));
  });

  // A tile parked for a start board the snapshot never brings: one pull per sync,
  // not one sync after the other for as long as the device is online.
  test(
    'a parked entry without its board does not keep the sync running',
    () async {
      await db
          .into(db.outboxEntries)
          .insert(
            OutboxEntriesCompanion.insert(
              mutationId: 'm1',
              entityType: 'WIDGET',
              entityId: 'w1',
              op: 'upsert',
              fields: const Value('{}'),
              state: const Value('parked'),
              errorCode: const Value('board:START:orphan'),
              createdAt: DateTime.now(),
            ),
          );
      final engine = container.read(syncEngineProvider);

      await engine.syncNow();
      expect(server.pulls, equals(1));

      for (int run = 1; run < 20; run++) {
        await engine.syncNow();
      }
      final entry = await db.select(db.outboxEntries).getSingle();
      expect(entry.state, equals('rejected'));
      expect(entry.errorCode, equals('sync.board_gone'));
    },
  );

  // An answer this version cannot place — here a status it does not know — leaves
  // the batch in the queue: the run goes on to the pull instead of resending it.
  test('a full batch that stays pending is not resent in a loop', () async {
    for (int i = 0; i < 60; i++) {
      await container
          .read(outboxProvider)
          .add(
            entityType: 'TODO_LIST',
            entityId: 'l$i',
            op: 'upsert',
            fields: {'name': 'List $i'},
          );
    }
    server.pushStatus = 'from_the_future';

    await container.read(syncEngineProvider).syncNow();

    expect(server.pushes, equals(1));
    expect(server.pulls, equals(1));
  });

  test('a sync asked for during a run completes after the next run', () async {
    final engine = container.read(syncEngineProvider);
    final release = server.holdPull = Completer();
    final first = engine.syncNow();
    await server.pullStarted.future;

    await edit('Garden');
    bool secondDone = false;
    final second = engine.syncNow().then((_) => secondDone = true);
    await Future<void>.delayed(Duration.zero);
    expect(secondDone, isFalse, reason: 'it waits for the run in progress');

    release.complete();
    await first;
    await second;
    expect(server.pushed, contains('Garden'));
  });
  // Not the server's answer but something on this side: it used to end the run
  // without a word and without a retry, and every later run stopped at the same page.
  test('a failure on this side is shown and tried again', () async {
    final engine = container.read(syncEngineProvider);
    server.brokenPull = true;

    await expectLater(engine.syncNow(), throwsA(isA<TypeError>()));

    expect(engine.state.lastAttemptFailed, isTrue);
    expect(engine.retryScheduled, isTrue);
    await engine.stop();
  });

  // A background run pushing the same outbox: the app's run used to step aside at
  // once, the sign-out took that for "synced" and cleared the device under it.
  test('the last sync before sign-out waits for a background run', () async {
    final background = _Background(runs: 2);
    final waiting = ProviderContainer(
      parent: container,
      overrides: [
        backgroundSyncProvider.overrideWithValue(background),
        syncEngineProvider.overrideWith((ref) => syncEngine(ref)),
      ],
    );
    addTearDown(waiting.dispose);
    await edit('Groceries');

    await waiting.read(syncEngineProvider).syncLast();

    expect(background.asked, greaterThanOrEqualTo(3));
    expect(server.pushed, equals(['Groceries']));
  });
}

const _instance = '00000000-0000-0000-0000-00000000000a';

Map<String, dynamic> _list(String id, String name) => {
  'seq': 8,
  'entityType': 'TODO_LIST',
  'entityId': id,
  'op': 'upsert',
  'version': 8,
  'ownerId': 'anna',
  'fields': {'name': name},
};

const _signedIn = SessionState(
  stage: .signedIn,
  serverAddress: 'http://hiwiski.test',
  session: Session(
    member: Member(
      id: 'anna',
      username: 'anna',
      displayName: 'Anna',
      isAdmin: true,
      colorToken: .blue,
    ),
    deviceId: '00000000-0000-0000-0000-000000000001',
    mustChangePassword: false,
  ),
);

/// A background run that is still under way for [runs] more questions.
class _Background implements BackgroundSync {
  _Background({required this.runs});

  int runs;
  int asked = 0;

  @override
  Future<void> sessionChanged({required bool signedIn}) async {}

  @override
  Future<bool> runningElsewhere() async {
    asked++;
    return runs-- > 0;
  }
}

class _Tokens implements TokenStore {
  String? token = 'token';

  @override
  Future<String?> read() async => token;

  @override
  Future<String?> readPersisted() => read();

  @override
  Future<void> write(String value, {bool persist = true}) async =>
      token = value;

  @override
  Future<void> clear() async => token = null;
}

/// Push, pull and logout. The first pull can be held back to stand for one that is
/// still on its way.
class _FakeServer implements HttpClientAdapter {
  Completer<void>? holdPull;
  final pullStarted = Completer<void>();
  List<Map<String, dynamic>> pullAnswer = [];
  final pushed = <String>[];
  bool loggedOutAfterPush = false;
  bool loggedOut = false;

  /// Holds the logout back — a server that does not answer.
  Completer<void>? holdLogout;
  final logoutStarted = Completer<void>();
  String? logoutAuthorization;

  /// Hears an invitation being redeemed, before it is answered.
  AsyncCallback? onRedeem;
  int redeems = 0;
  bool unauthorized = false;
  int? failWith;

  /// The server was restored: every pull answers from this instance with this state.
  String? restoredTo;
  List<Object> restoredState = const [];
  String failCode = 'server.error';
  int pulls = 0;
  int pushes = 0;
  String pushStatus = 'applied';

  /// The next pull brings a change this app cannot take — a broken field.
  bool brokenPull = false;
  final _authorizations = <(String, String?)>[];

  /// The `Authorization` headers that went to [host].
  List<String?> authorizationsTo(String host) => [
    for (final (to, header) in _authorizations)
      if (to == host) header,
  ];
  bool offline = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    _authorizations.add((
      options.uri.host,
      options.headers['Authorization'] as String?,
    ));
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    if (failWith != null && path.endsWith('/api/v1/sync/pull')) {
      return ResponseBody.fromString(
        jsonEncode({'code': failCode}),
        failWith!,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (unauthorized) {
      return ResponseBody.fromString(
        jsonEncode({'code': 'auth.required'}),
        401,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (path.endsWith('/api/v1/auth/logout')) {
      logoutAuthorization = options.headers['Authorization'] as String?;
      if (holdLogout case final hold?) {
        logoutStarted.complete();
        await hold.future;
      }
      loggedOut = true;
      loggedOutAfterPush = pushed.isNotEmpty;
      return ResponseBody.fromString('', 204);
    }
    if (path.endsWith('/redeem')) {
      redeems++;
      await onRedeem?.call();
      return ResponseBody.fromString(
        jsonEncode({'code': 'invitation.invalid'}),
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    final body = jsonDecode(jsonEncode(options.data)) as Map<String, dynamic>;
    if (path.endsWith('/api/v1/sync/push')) {
      pushes++;
      final mutations = (body['mutations'] as List)
          .cast<Map<String, dynamic>>();
      pushed.addAll([
        for (final mutation in mutations)
          (mutation['fields'] as Map)['name'] as String,
      ]);
      return _json({
        'latestSeq': 9,
        'results': [
          for (final mutation in mutations)
            {
              'mutationId': mutation['mutationId'],
              'status': pushStatus,
              'entityId': mutation['entityId'],
              'version': 9,
            },
        ],
      });
    }
    if (path.endsWith('/api/v1/sync/pull')) {
      pulls++;
      if (restoredTo case final instance?) {
        return _json({..._page(restoredState, 20), 'instanceId': instance});
      }
      final hold = holdPull;
      if (hold != null) {
        holdPull = null;
        if (!pullStarted.isCompleted) pullStarted.complete();
        await hold.future;
        final answer = pullAnswer;
        pullAnswer = [];
        return _json(_page(answer, answer.isEmpty ? body['lastSeq'] : 8));
      }
      if (brokenPull) {
        brokenPull = false;
        return _json(
          _page([
            {
              'seq': 8,
              'op': 'upsert',
              'entityType': 'TODO_LIST',
              'entityId': 'l9',
              'version': 8,
              'ownerId': 'anna',
              'fields': {'position': 'first'},
            },
          ], 8),
        );
      }
      return _json(_page(const [], body['lastSeq']));
    }
    throw StateError('unexpected request ${options.method} $path');
  }

  static Map<String, dynamic> _page(List<Object> changes, Object? latest) => {
    'changes': changes,
    'latestSeq': latest,
    'hasMore': false,
    'instanceId': _instance,
    'resyncRequired': false,
  };

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
