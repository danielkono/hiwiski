import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/api/hiwiski_failure.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/storage/token_store.dart';
import 'package:hiwiski/core/sync/pending_shares.dart';
import 'package:hiwiski/core/sync/sync_engine.dart';
import 'package:hiwiski/data/access/access_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hiwiski/domain/common/item_ref.dart';

/// **Sharing works offline** — from the sheet seen last, and the change goes out with
/// the next sync run.
void main() {
  late _FakeServer server;
  late LocalSettings settings;
  late PendingShares pending;
  late AccessRepository repository;

  const target = ItemRef('TODO_LIST', 'list-1');
  const anna = '00000000-0000-0000-0000-0000000000a1';
  const ben = '00000000-0000-0000-0000-0000000000b1';
  const kids = '00000000-0000-0000-0000-0000000000c1';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await LocalSettings.open();
    server = _FakeServer({
      'itemType': target.type,
      'itemId': target.id,
      'mayEdit': true,
      'ownerId': anna,
      'myLevel': 'WRITE',
      'entries': [
        {
          'subjectType': 'MEMBER',
          'subjectId': anna,
          'level': 'WRITE',
          'source': 'OWNER',
        },
        {
          'subjectType': 'GROUP',
          'subjectId': kids,
          'level': 'READ',
          'source': 'INHERITED',
        },
      ],
    });
    final api = HiwiskiApi(tokens: _Tokens(), baseUrl: 'http://hiwiski.test');
    api.dio.httpClientAdapter = server;
    pending = PendingShares(settings: settings, api: api);
    repository = AccessRepository(
      api: api,
      pendingShares: pending,
      settings: settings,
      sync: _NoSync(),
    );
  });

  const toBen = WriteShare(subjectType: .member, subjectId: ben, level: .check);

  test('offline the sheet opens as last seen', () async {
    await repository.shareSheet(target);
    server.offline = true;

    final sheet = await repository.shareSheet(target);
    expect(sheet.mayEdit, isTrue);
    expect(sheet.entries.map((entry) => entry.subjectId), equals([anna, kids]));
  });

  test('a sheet never seen does not open offline', () async {
    server.offline = true;
    await expectLater(
      repository.shareSheet(target),
      throwsA(isA<HiwiskiFailure>()),
    );
  });

  test(
    'a change offline shows at once and goes out with the next run',
    () async {
      await repository.shareSheet(target);
      server.offline = true;

      await repository.setShares(target, const [toBen]);
      final sheet = await repository.shareSheet(target);
      // Own shares replace inheritance.
      expect(
        sheet.entries.map((entry) => (entry.subjectId, entry.source)),
        equals([(anna, ShareSource.owner), (ben, ShareSource.direct)]),
      );
      expect(server.written, isEmpty);

      server.offline = false;
      await pending.flush();
      expect(server.written, hasLength(1));
      expect(
        server.written.single['shares'],
        equals([
          {'subjectType': 'MEMBER', 'subjectId': ben, 'level': 'CHECK'},
        ]),
      );
      expect(settings.pendingShares, isEmpty);
    },
  );

  // A list shared from its sheet while a sync was sending other shares: the flush used
  // to write back the list as it was before its calls, and the new share was lost.
  test('a share queued during a flush stays queued', () async {
    await pending.queue(
      itemType: target.type,
      itemId: target.id,
      shares: const [toBen],
    );
    final release = server.holdPut = Completer();
    final flushing = pending.flush();
    await server.putStarted.future;

    await pending.queue(
      itemType: 'TODO_LIST',
      itemId: 'list-2',
      shares: const [toBen],
    );
    release.complete();
    await flushing;

    expect(settings.pendingShares, hasLength(1));
    expect(settings.pendingShares.single, contains('list-2'));
  });

  test('an online change drops the offline one still waiting', () async {
    await repository.shareSheet(target);
    server.offline = true;
    await repository.setShares(target, const []);

    server.offline = false;
    await repository.setShares(target, const [toBen]);
    await pending.flush();

    // Only the online write went out; the older offline one did not follow it.
    expect(server.written, hasLength(1));
    expect(server.written.single['shares'], hasLength(1));
    expect(settings.pendingShares, isEmpty);
  });

  // The item's create was refused and discarded: the server will never know it.
  test('a share for an item the server never gets is given up', () async {
    await pending.queue(
      itemType: target.type,
      itemId: target.id,
      shares: const [toBen],
    );
    server.notFound = true;

    for (int run = 1; run < 20; run++) {
      await pending.flush();
      expect(settings.pendingShares, hasLength(1), reason: 'run $run');
    }
    await pending.flush();
    expect(settings.pendingShares, isEmpty);
  });

  test('only the last offline change for an item goes out', () async {
    await repository.shareSheet(target);
    server.offline = true;

    await repository.setShares(target, const [toBen]);
    await repository.setShares(target, const []);

    server.offline = false;
    await pending.flush();
    expect(server.written, hasLength(1));
    expect(server.written.single['shares'], isEmpty);
  });
}

class _FakeServer implements HttpClientAdapter {
  _FakeServer(this.sheet);

  final Map<String, dynamic> sheet;
  final written = <Map<String, dynamic>>[];
  bool offline = false;
  Completer<void>? holdPut;
  bool notFound = false;
  final putStarted = Completer<void>();

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
    if (notFound && options.method == 'PUT') {
      return ResponseBody.fromString(
        jsonEncode({'code': 'access.item_not_found'}),
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.method == 'PUT') {
      final hold = holdPut;
      if (hold != null) {
        holdPut = null;
        putStarted.complete();
        await hold.future;
      }
      final body = options.data;
      written.add(
        body is String
            ? jsonDecode(body) as Map<String, dynamic>
            : jsonDecode(jsonEncode(body)) as Map<String, dynamic>,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(sheet),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _NoSync implements SyncTrigger {
  @override
  Future<void> syncNow() async {}
}

class _Tokens implements TokenStore {
  @override
  Future<String?> read() async => 'token';

  @override
  Future<String?> readPersisted() => read();

  @override
  Future<void> write(String token, {bool persist = true}) async {}

  @override
  Future<void> clear() async {}
}
