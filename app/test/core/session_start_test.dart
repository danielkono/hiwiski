import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/storage/token_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **Whoever was signed in starts signed in.**
///
/// The start used to wait for the handshake on the sign-in screen: online it flickered,
/// offline after a force quit the app could not be used at all — although the data was
/// on the device.
void main() {
  late HiwiskiDatabase db;
  late _FakeServer server;
  late _Tokens tokens;

  const handshake = {
    'apiVersion': 'v1',
    'serverVersion': '2026.10.0',
    'minClientVersion': '0.0.0',
    'setupCompleted': true,
    'cleartext': false,
    'familyName': 'Berger',
  };
  const session = {
    'member': {
      'id': '00000000-0000-0000-0000-0000000000a1',
      'username': 'anna',
      'displayName': 'Anna',
      'isAdmin': false,
      'colorToken': 'BLUE',
    },
    'deviceId': '00000000-0000-0000-0000-000000000001',
    'mustChangePassword': false,
  };

  Future<ProviderContainer> start({
    String? remembered,
    bool wipe = false,
    String? lost,
  }) async {
    SharedPreferences.setMockInitialValues({
      'hiwiski.server.address': 'http://hiwiski.test',
      'hiwiski.session.last': ?remembered,
      'hiwiski.session.lost': ?lost,
      if (wipe) 'hiwiski.access_lost.wipe': true,
    });
    final settings = await LocalSettings.open();
    final api = HiwiskiApi(tokens: tokens, baseUrl: 'http://hiwiski.test');
    api.dio.httpClientAdapter = server;
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
        tokenStoreProvider.overrideWithValue(tokens),
        hiwiskiApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  final remembered = jsonEncode({'session': session, 'handshake': handshake});
  const ben = {
    'member': {
      'id': '00000000-0000-0000-0000-0000000000b2',
      'username': 'ben',
      'displayName': 'Ben',
      'isAdmin': false,
      'colorToken': 'BLUE',
    },
    'deviceId': '00000000-0000-0000-0000-000000000002',
    'mustChangePassword': false,
  };

  setUp(() {
    db = HiwiskiDatabase(NativeDatabase.memory());
    server = _FakeServer(handshake: handshake, session: session);
    tokens = _Tokens('token');
  });

  tearDown(() => db.close());

  Future<void> holdData() async {
    await db.setOwner(
      '00000000-0000-0000-0000-0000000000a1@http://hiwiski.test',
    );
    await db.setLastSeq(7);
    await db
        .into(db.todoLists)
        .insert(TodoListsCompanion.insert(id: 'l1', ownerId: 'anna'));
  }

  test('a remembered session is signed in on the very first frame', () async {
    server.offline = true;
    final container = await start(remembered: remembered);

    final first = container.read(sessionProvider);
    expect(first.stage, equals(SessionStage.signedIn));
    expect(first.member?.displayName, equals('Anna'));
    expect(first.handshake?.familyName, equals('Berger'));
  });

  test('offline it stays signed in once the handshake fails', () async {
    server.offline = true;
    final container = await start(remembered: remembered);
    container.read(sessionProvider);

    await container.read(sessionStoreProvider).refresh();

    expect(
      container.read(sessionProvider).stage,
      equals(SessionStage.signedIn),
    );
  });

  // Locked, not signed out: the device keeps whom its data belongs to, and the start
  // does not open it again on the remembered session.
  test(
    'a revoked token locks the device and forgets the remembered session',
    () async {
      server.unauthorized = true;
      final container = await start(remembered: remembered);
      container.read(sessionProvider);

      await container.read(sessionStoreProvider).refresh();

      expect(
        container.read(sessionProvider).stage,
        equals(SessionStage.accessLost),
      );
      expect(container.read(sessionProvider).member?.username, equals('anna'));
      expect(container.read(localSettingsProvider).lastSession, isNull);
      expect(container.read(localSettingsProvider).lostSession, isNotNull);
      expect(await tokens.read(), isNull);
    },
  );

  // A device signed out from another one keeps its data, locked — changes made offline
  // were lost with it.
  test("a token revoked on start keeps the family's data, locked", () async {
    await holdData();
    server.unauthorized = true;
    final container = await start(remembered: remembered);
    container.read(sessionProvider);

    await container.read(sessionStoreProvider).refresh();

    expect(await db.select(db.todoLists).get(), hasLength(1));
    expect(await db.owner, isNotNull);
  });

  // Account → Customize: "Delete everything at once" — for a device that may be lost.
  test('a token revoked on start clears the data if chosen so', () async {
    await holdData();
    server.unauthorized = true;
    final container = await start(remembered: remembered, wipe: true);
    container.read(sessionProvider);

    await container.read(sessionStoreProvider).refresh();

    expect(
      container.read(sessionProvider).stage,
      equals(SessionStage.signedOut),
    );
    expect(await db.select(db.todoLists).get(), isEmpty);
    expect(await db.owner, isNull);
    expect(await db.lastSeq, equals(0));
  });

  test('a remembered session without a token is locked, not open', () async {
    tokens = _Tokens(null);
    final container = await start(remembered: remembered);
    container.read(sessionProvider);
    await pumpEventQueue();

    await container.read(sessionStoreProvider).refresh();

    expect(
      container.read(sessionProvider).stage,
      equals(SessionStage.accessLost),
    );
    expect(container.read(localSettingsProvider).lastSession, isNull);
  });

  test('a confirmed session is remembered for the next start', () async {
    final container = await start();
    expect(
      container.read(sessionProvider).stage,
      equals(SessionStage.unreachable),
    );

    await container.read(sessionStoreProvider).refresh();

    expect(
      container.read(sessionProvider).stage,
      equals(SessionStage.signedIn),
    );
    final next = await start(
      remembered: container.read(localSettingsProvider).lastSession,
    );
    expect(next.read(sessionProvider).stage, equals(SessionStage.signedIn));
    expect(next.read(sessionProvider).member?.username, equals('anna'));
  });

  test('without a remembered session the start waits for the server', () async {
    server.offline = true;
    final container = await start();

    await container.read(sessionStoreProvider).refresh();

    expect(
      container.read(sessionProvider).stage,
      equals(SessionStage.unreachable),
    );
  });

  // A sign-in without "Stay signed in" keeps its token for that run only. Started
  // again, the app showed the sign-in — and the member's data stayed on the device,
  // readable in the browser's developer tools, until someone else signed in.
  test('a start without a token locks what is left of the session', () async {
    await holdData();
    tokens = _Tokens(null);
    final container = await start(remembered: remembered);
    container.read(sessionProvider);
    await pumpEventQueue();

    expect(
      container.read(sessionProvider).stage,
      equals(SessionStage.accessLost),
    );
    expect(await db.select(db.todoLists).get(), hasLength(1));
    expect(await db.owner, isNotNull);
  });

  test('a start with a token leaves the data alone', () async {
    await holdData();
    server.offline = true;
    final container = await start(remembered: remembered);
    container.read(sessionProvider);
    await pumpEventQueue();

    expect(await db.select(db.todoLists).get(), hasLength(1));
  });

  test('after a restart a locked device is still locked', () async {
    final container = await start(lost: jsonEncode(session));

    expect(
      container.read(sessionProvider).stage,
      equals(SessionStage.accessLost),
    );
    expect(container.read(sessionProvider).member?.displayName, equals('Anna'));
  });

  test('signing in again as the same member opens the data', () async {
    await holdData();
    server.unauthorized = true;
    final container = await start(remembered: remembered);
    container.read(sessionProvider);
    // The start's own handshake finds the token revoked: locked.
    await pumpEventQueue(times: 50);
    expect(
      container.read(sessionProvider).stage,
      equals(SessionStage.accessLost),
    );
    // Signed in again: a fresh token, and the session confirmed.
    server.unauthorized = false;
    await tokens.write('fresh-token');

    await container.read(sessionStoreProvider).refresh();

    expect(
      container.read(sessionProvider).stage,
      equals(SessionStage.signedIn),
    );
    expect(await db.select(db.todoLists).get(), hasLength(1));
    expect(container.read(localSettingsProvider).lostSession, isNull);
  });

  test('signing in as someone else clears the locked data', () async {
    await holdData();
    server.unauthorized = true;
    final container = await start(remembered: remembered);
    container.read(sessionProvider);
    // The start's own handshake finds the token revoked: locked.
    await pumpEventQueue(times: 50);
    expect(
      container.read(sessionProvider).stage,
      equals(SessionStage.accessLost),
    );
    server
      ..unauthorized = false
      ..signsIn = ben;
    await tokens.write('bens-token');

    await container.read(sessionStoreProvider).refresh();

    expect(container.read(sessionProvider).member?.username, equals('ben'));
    expect(await db.select(db.todoLists).get(), isEmpty);
    expect(container.read(localSettingsProvider).lostSession, isNull);
  });

  test('"Sign out and delete data" clears the locked device', () async {
    await holdData();
    server.unauthorized = true;
    final container = await start(remembered: remembered);
    container.read(sessionProvider);
    await container.read(sessionStoreProvider).refresh();

    await container.read(sessionStoreProvider).discardAfterAccessLost();

    expect(
      container.read(sessionProvider).stage,
      equals(SessionStage.signedOut),
    );
    expect(await db.select(db.todoLists).get(), isEmpty);
    expect(await db.owner, isNull);
    expect(container.read(localSettingsProvider).lostSession, isNull);
  });
}

class _Tokens implements TokenStore {
  _Tokens(this._token);

  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<String?> readPersisted() => read();

  @override
  Future<void> write(String token, {bool persist = true}) async =>
      _token = token;

  @override
  Future<void> clear() async => _token = null;
}

class _FakeServer implements HttpClientAdapter {
  _FakeServer({required this.handshake, required this.session});

  final Map<String, dynamic> handshake;
  final Map<String, dynamic> session;
  bool offline = false;
  bool unauthorized = false;

  /// Whom the session belongs to once signed in again — the member of [session]
  /// unless set.
  Map<String, dynamic>? signsIn;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    if (options.path.endsWith('/api/v1/handshake')) return _json(handshake);
    if (unauthorized) {
      return _json({'code': 'auth.unauthorized', 'message': 'gone'}, 401);
    }
    return _json(signsIn ?? session);
  }

  ResponseBody _json(Object body, [int status = 200]) => .fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
