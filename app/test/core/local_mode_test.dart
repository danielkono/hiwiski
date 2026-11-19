import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/storage/token_store.dart';
import 'package:hiwiski/domain/common/server_address.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **Used without a server, then taken to one**.
///
/// The member is made on the device; nothing asks a server. Connecting keeps the
/// data: the setup and the invitation create the member under the same id, signing
/// in to an account rewrites it — and either way the outbox is what goes out.
void main() {
  late HiwiskiDatabase db;
  late _FakeServer server;
  late _Tokens tokens;
  late HiwiskiApi api;

  Future<ProviderContainer> start({
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final settings = await LocalSettings.open();
    api = HiwiskiApi(tokens: tokens, baseUrl: settings.serverAddress);
    api.dio.httpClientAdapter = server;
    final container = ProviderContainer(
      retry: noRetry,
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
        tokenStoreProvider.overrideWithValue(tokens),
        hiwiskiApiProvider.overrideWithValue(api),
        deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    db = HiwiskiDatabase(NativeDatabase.memory());
    server = _FakeServer();
    tokens = _Tokens();
  });

  tearDown(() => db.close());

  Future<String> startLocal(ProviderContainer container) async {
    container.read(sessionProvider);
    await container.read(sessionStoreProvider).startLocal('Anna');
    return container.read(sessionProvider).member!.id;
  }

  Future<String> someData(ProviderContainer container) async {
    final todos = container.read(todoRepositoryProvider);
    final list = await todos.createList(name: 'Home', kind: 'STANDARD');
    await todos.createTodo(listId: list, title: 'Bins');
    final todo = (await todos.watchTodos(list).first).single;
    await todos.updateTodo(todo, title: 'Bins out');
    return list;
  }

  test('started without a server, nothing asks one', () async {
    final container = await start();
    expect(
      container.read(sessionProvider).stage,
      equals(SessionStage.noServer),
    );

    final me = await startLocal(container);
    await someData(container);
    await container.read(syncRepositoryProvider).syncNow();

    final session = container.read(sessionProvider);
    expect(session.stage, equals(SessionStage.localOnly));
    expect(session.hasServer, isFalse);
    expect(await db.owner, equals('$me@local'));
    expect(container.read(syncStatusProvider).answered, isTrue);
    expect(
      await container.read(familyRepositoryProvider).watchMembers().first,
      equals([isA<Member>().having((m) => m.displayName, 'name', 'Anna')]),
    );
    expect(server.requests, isEmpty);
  });

  test(
    'the next start is without a server again, on the same member',
    () async {
      final first = await start();
      final me = await startLocal(first);
      final prefs = {
        'hiwiski.local.member': first.read(localSettingsProvider).localMember!,
      };

      final next = await start(prefs: prefs);

      expect(next.read(sessionProvider).stage, equals(SessionStage.localOnly));
      expect(next.read(sessionProvider).member?.id, equals(me));
    },
  );

  test(
    'the setup takes the member over under the same id, data and all',
    () async {
      final container = await start();
      final me = await startLocal(container);
      final list = await someData(container);
      final store = container.read(sessionStoreProvider);

      await store.connect(ServerAddress.parse('hiwiski.test')!);
      expect(
        container.read(sessionProvider).stage,
        equals(SessionStage.setupRequired),
      );
      expect(store.connectingFromLocal, isTrue);
      // Nothing is taken over before the server has the member.
      expect(await db.owner, equals('$me@local'));

      await store.runSetup(
        const SetupRequest(
          familyName: 'Berger',
          timezone: 'Europe/Berlin',
          admin: SetupAdmin(
            displayName: 'Anna',
            username: 'anna',
            password: 'geheim-genug',
          ),
          device: DeviceRegistration(deviceName: 'Test', platform: .ios),
        ),
      );

      expect(server.setupAdminId, equals(me));
      final session = container.read(sessionProvider);
      expect(session.stage, equals(SessionStage.signedIn));
      expect(session.member?.id, equals(me));
      expect(await db.owner, equals('$me@${server.base}'));
      expect(container.read(localSettingsProvider).localMember, isNull);
      expect(container.read(localSettingsProvider).catalogCarryover, isTrue);
      expect(container.read(localSettingsProvider).appearancePending, isTrue);
      // One creation per item, the list first.
      final outbox = await (db.select(
        db.outboxEntries,
      )..orderBy([(entry) => OrderingTerm.asc(entry.createdAt)])).get();
      expect(
        outbox.map((entry) => entry.entityType),
        equals(['TODO_LIST', 'TODO']),
      );
      expect(outbox.first.entityId, equals(list));
      expect(await db.select(db.todos).get(), hasLength(1));
    },
  );

  test('an invitation takes the member over under the same id', () async {
    final container = await start();
    final me = await startLocal(container);
    await someData(container);
    final store = container.read(sessionStoreProvider);
    server.setUp = true;
    await store.connect(ServerAddress.parse('hiwiski.test')!);

    await store.redeemInvitation(
      'ABC1234',
      const RedeemInvitationRequest(
        displayName: 'Anna',
        username: 'anna',
        password: 'geheim-genug',
        device: DeviceRegistration(deviceName: 'Test', platform: .ios),
      ),
    );

    expect(server.redeemedMemberId, equals(me));
    expect(await db.owner, equals('$me@${server.base}'));
    expect(await db.select(db.todoLists).get(), hasLength(1));
  });

  test('signing in to an account the server has rewrites the member', () async {
    final container = await start();
    final me = await startLocal(container);
    await someData(container);
    final store = container.read(sessionStoreProvider);
    server.setUp = true;
    await store.connect(ServerAddress.parse('hiwiski.test')!);

    // Signed in: a token, and the account's session — the path a sign-in takes once
    // the server has answered.
    server.signedInAs(_FakeServer.accountId);
    await tokens.write('token');
    await store.refresh();

    const account = _FakeServer.accountId;
    expect(container.read(sessionProvider).member?.id, equals(account));
    expect(await db.owner, equals('$account@${server.base}'));
    final list = (await db.select(db.todoLists).get()).single;
    expect(list.ownerId, equals(account));
    final outbox = await db.select(db.outboxEntries).get();
    expect(outbox, hasLength(2));
    expect(outbox.map((entry) => entry.fields).join(), isNot(contains(me)));
    expect(container.read(localSettingsProvider).localMember, isNull);
  });

  test('back from the server address, everything is as it was', () async {
    final container = await start();
    final me = await startLocal(container);
    await someData(container);
    final store = container.read(sessionStoreProvider);
    await store.connect(ServerAddress.parse('hiwiski.test')!);

    await store.backToLocal();

    final session = container.read(sessionProvider);
    expect(session.stage, equals(SessionStage.localOnly));
    expect(session.member?.id, equals(me));
    expect(container.read(localSettingsProvider).serverAddress, isNull);
    expect(await db.owner, equals('$me@local'));
    expect(await db.select(db.todoLists).get(), hasLength(1));
  });

  test('a restart on the way to a server neither locks nor clears', () async {
    final first = await start();
    final me = await startLocal(first);
    await someData(first);
    await first
        .read(sessionStoreProvider)
        .connect(ServerAddress.parse('hiwiski.test')!);
    final prefs = {
      'hiwiski.local.member': first.read(localSettingsProvider).localMember!,
      'hiwiski.server.address': server.base,
    };

    final next = await start(prefs: prefs);
    next.read(sessionProvider);
    await pumpEventQueue(times: 50);

    expect(
      next.read(sessionProvider).stage,
      equals(SessionStage.setupRequired),
    );
    expect(next.read(sessionStoreProvider).connectingFromLocal, isTrue);
    expect(await db.owner, equals('$me@local'));
    expect(await db.select(db.todoLists).get(), hasLength(1));
  });

  test('"Delete everything" leaves nothing and starts anew', () async {
    final container = await start();
    await startLocal(container);
    await someData(container);

    await container.read(sessionStoreProvider).discardLocal();

    expect(
      container.read(sessionProvider).stage,
      equals(SessionStage.noServer),
    );
    expect(container.read(localSettingsProvider).localMember, isNull);
    expect(await db.select(db.todoLists).get(), isEmpty);
    expect(await db.select(db.outboxEntries).get(), isEmpty);
    expect(await db.owner, isNull);
  });
}

class _Tokens implements TokenStore {
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

/// A server that is set up by the test, and remembers who it was asked to create.
class _FakeServer implements HttpClientAdapter {
  static const accountId = '00000000-0000-0000-0000-0000000000a1';

  final base = 'http://hiwiski.test';
  final requests = <String>[];
  bool setUp = false;
  String? setupAdminId;
  String? redeemedMemberId;
  Map<String, dynamic>? _session;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    requests.add('${options.method} $path');
    // Through JSON, as the server would see it: nested models become maps.
    final body = switch (options.data) {
      null => const <String, dynamic>{},
      final String text => jsonDecode(text) as Map<String, dynamic>,
      final data => jsonDecode(jsonEncode(data)) as Map<String, dynamic>,
    };
    if (path.endsWith('/handshake')) {
      return _json({
        'apiVersion': 'v1',
        'serverVersion': '2026.10.0',
        'minClientVersion': '0.0.0',
        'setupCompleted': setUp,
        'cleartext': false,
        'familyName': 'Berger',
      });
    }
    if (path.endsWith('/setup')) {
      setUp = true;
      final admin = body['admin'] as Map<String, dynamic>;
      setupAdminId = admin['id'] as String?;
      return _signedIn(setupAdminId ?? accountId, 'anna');
    }
    if (path.endsWith('/redeem')) {
      redeemedMemberId = body['memberId'] as String?;
      return _signedIn(redeemedMemberId ?? accountId, 'anna');
    }
    if (path.endsWith('/auth/login')) return _signedIn(accountId, 'anna');
    if (path.endsWith('/auth/session')) return _json(_session ?? {});
    // The sync and everything else: nothing there yet.
    return _json({'code': 'not_found', 'message': 'nothing here'}, 404);
  }

  /// The session the server answers with from now on.
  void signedInAs(String id) => _signedIn(id, 'anna');

  ResponseBody _signedIn(String id, String username) {
    _session = {
      'member': {
        'id': id,
        'username': username,
        'displayName': 'Anna',
        'isAdmin': true,
        'colorToken': 'GREEN',
      },
      'deviceId': '00000000-0000-0000-0000-000000000001',
      'mustChangePassword': false,
    };
    return _json({'token': 'token', 'session': _session});
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
