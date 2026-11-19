import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/api/hiwiski_failure.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/db/tables.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/common/sync_limits.dart';
import 'package:hiwiski/domain/common/change.dart';
import 'package:hiwiski/domain/common/text_length.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

/// The server's limits on a push neither stop the sync nor
/// pile up rejections.
void main() {
  late HiwiskiDatabase db;
  late _FakeServer server;
  late ProviderContainer container;

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

  Future<void> queue(String mutationId, int second) => db
      .into(db.outboxEntries)
      .insert(
        OutboxEntriesCompanion.insert(
          mutationId: mutationId,
          entityType: 'TODO_LIST',
          entityId: 'list-$mutationId',
          op: 'upsert',
          fields: const Value('{"name":"List"}'),
          createdAt: DateTime(2026, 11, 2, 8, 0, second),
        ),
      );

  test('a push refused as too large is halved, a single mutation still '
      'refused is rejected visibly, and the pull happens anyway', () async {
    for (int i = 0; i < 5; i++) {
      await queue('m$i', i);
    }
    server
      ..maxMutations = 2
      ..poison = 'm3';

    await container.read(syncEngineProvider).syncNow();

    expect(server.pulls, isNotEmpty);
    final left = await db.select(db.outboxEntries).get();
    expect(left.map((entry) => entry.mutationId), equals(['m3']));
    expect(left.single.state, equals(OutboxStates.rejected));
    expect(left.single.errorCode, equals(FailureCodes.requestTooLarge));
    expect(server.pushed.first, equals(5));
    expect(server.pushed.every((count) => count <= 5), isTrue);
  });

  test('another 400 on the push leaves the outbox alone', () async {
    await queue('m0', 0);
    server.refuseWith = 'identity.device_not_found';

    await expectLater(
      container.read(syncEngineProvider).syncNow(),
      throwsA(isA<HiwiskiFailure>()),
    );

    final entry = (await db.select(db.outboxEntries).get()).single;
    expect(entry.state, equals(OutboxStates.pending));
  });

  /// A device that has synced before: the pull reads the log, no snapshot clears
  /// what the fake server does not know.
  Future<void> synced() async {
    await db.setOwner('anna@http://hiwiski.test');
    await db.setInstanceId('00000000-0000-0000-0000-00000000000a');
    await db.setLastSeq(1);
  }

  final tooLong = 'x' * (SyncLimits.textChars + 1);

  Future<OutboxRow> entryOf(String mutationId) => (db.select(
    db.outboxEntries,
  )..where((row) => row.mutationId.equals(mutationId))).getSingle();

  test('a value beyond the server limit is saved on the device and held, '
      'not sent; shortened, it syncs', () async {
    await synced();
    final repository = container.read(todoRepositoryProvider);
    final id = await repository.createList(name: 'Notes', kind: 'STANDARD');
    await container.read(syncEngineProvider).syncNow();
    expect(await db.select(db.outboxEntries).get(), isEmpty);
    final list = (await repository.watchList(id).first)!;

    await repository.updateList(list, description: Change(tooLong));
    await container.read(syncEngineProvider).syncNow();

    // Saved: leaving the page loses nothing.
    expect(
      (await repository.watchList(id).first)!.description,
      equals(tooLong),
    );
    // Held: visible with the changes that cannot be synced, and never sent.
    final held = (await db.select(db.outboxEntries).get()).single;
    expect(held.state, equals(OutboxStates.rejected));
    expect(held.errorCode, equals(FailureCodes.syncValueTooLarge));
    expect(server.sent, isNot(contains(held.mutationId)));

    // "Try again" does not send it either.
    await container.read(syncRepositoryProvider).retryStuck();
    expect(
      (await entryOf(held.mutationId)).state,
      equals(OutboxStates.rejected),
    );
    expect(server.sent, isNot(contains(held.mutationId)));

    final longer = (await repository.watchList(id).first)!;
    await repository.updateList(longer, description: const Change('Short'));
    await container.read(syncEngineProvider).syncNow();

    expect(await db.select(db.outboxEntries).get(), isEmpty);
    expect(server.sentFields.last['description'], equals('Short'));
    expect(
      server.sentFields.map((fields) => fields['description']),
      isNot(contains(tooLong)),
    );
  });

  test('what the held change still carries goes out once the long value is '
      'replaced', () async {
    await synced();
    final repository = container.read(todoRepositoryProvider);
    final id = await repository.createList(name: 'Notes', kind: 'STANDARD');
    await container.read(syncEngineProvider).syncNow();
    final list = (await repository.watchList(id).first)!;
    await repository.updateList(
      list,
      name: 'Notes 2026',
      description: Change(tooLong),
    );
    final held = (await db.select(db.outboxEntries).get()).single;
    expect(held.state, equals(OutboxStates.rejected));

    final now = (await repository.watchList(id).first)!;
    await repository.updateList(now, description: const Change('Short'));

    final entry = await entryOf(held.mutationId);
    expect(entry.state, equals(OutboxStates.pending));
    expect(jsonDecode(entry.fields), equals({'name': 'Notes 2026'}));
  });

  test('a new item held back blocks what depends on it, and is released when '
      'shortened', () async {
    await synced();
    final repository = container.read(todoRepositoryProvider);
    final id = await repository.createList(
      name: 'Notes',
      kind: 'STANDARD',
      description: tooLong,
    );
    final list = (await repository.watchList(id).first)!;
    await repository.updateList(list, name: 'Renamed');

    final entries = await (db.select(
      db.outboxEntries,
    )..orderBy([(row) => OrderingTerm.asc(row.createdAt)])).get();
    expect(
      entries.map((entry) => entry.state),
      equals([OutboxStates.rejected, OutboxStates.blocked]),
    );

    final renamed = (await repository.watchList(id).first)!;
    await repository.updateList(renamed, description: const Change('Short'));

    final after = await db.select(db.outboxEntries).get();
    expect(
      after.map((entry) => entry.state),
      everyElement(OutboxStates.pending),
    );
  });

  test('the editor warns from 90 % of the limit on', () {
    const limit = SyncLimits.textChars;
    expect(textLengthOf('x' * (limit * 9 ~/ 10 - 1)), equals(TextLength.fits));
    expect(textLengthOf('x' * (limit * 9 ~/ 10)), equals(TextLength.nearLimit));
    expect(textLengthOf('x' * limit), equals(TextLength.nearLimit));
    expect(textLengthOf('x' * (limit + 1)), equals(TextLength.overLimit));
  });

  test('the limits are the server\'s', () {
    expect(SyncLimits.exceeded({'title': 'x' * SyncLimits.textChars}), isNull);
    expect(
      SyncLimits.exceeded({'title': 'x' * (SyncLimits.textChars + 1)}),
      equals('title'),
    );
    expect(
      SyncLimits.exceeded({
        'tags': [for (var i = 0; i <= SyncLimits.ids; i++) 't$i'],
      }),
      equals('tags'),
    );
    // A list order is JSON, not a list of ids: only its size counts.
    expect(
      SyncLimits.exceeded({
        'listIds': [for (var i = 0; i <= SyncLimits.ids; i++) 'l$i'],
      }),
      isNull,
    );
    expect(
      SyncLimits.exceeded({
        'exceptions': {
          for (var i = 0; i <= SyncLimits.mergedKeys; i++) 'k$i': true,
        },
      }),
      equals('exceptions'),
    );
    expect(
      SyncLimits.exceeded({
        'config': {'text': 'x' * SyncLimits.jsonChars},
      }),
      equals('config'),
    );
  });
}

class _FakeServer implements HttpClientAdapter {
  int maxMutations = 200;
  String? poison;
  String? refuseWith;
  final pushed = <int>[];

  /// The mutation ids that went out, and their fields.
  final sent = <String>[];
  final sentFields = <Map<String, dynamic>>[];
  final pulls = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = jsonDecode(jsonEncode(options.data)) as Map<String, dynamic>?;
    if (options.path.endsWith('/api/v1/sync/push')) {
      final mutations = (body!['mutations'] as List).cast<Map>();
      pushed.add(mutations.length);
      for (final mutation in mutations) {
        sent.add(mutation['mutationId'] as String);
        sentFields.add(
          (mutation['fields'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
      }
      if (refuseWith case final code?) {
        return _json({'code': code}, 400);
      }
      if (mutations.length > maxMutations ||
          mutations.any((mutation) => mutation['mutationId'] == poison)) {
        return _json({'code': 'request.too_large'}, 413);
      }
      return _json({
        'results': [
          for (final mutation in mutations)
            {
              'mutationId': mutation['mutationId'],
              'status': 'applied',
              'entityId': mutation['entityId'],
              'version': 1,
            },
        ],
        'latestSeq': 1,
      });
    }
    if (options.path.endsWith('/api/v1/sync/pull')) {
      pulls.add(body ?? const {});
      return _json({
        'changes': [],
        'latestSeq': 0,
        'hasMore': false,
        'instanceId': '00000000-0000-0000-0000-00000000000a',
        'resyncRequired': false,
      });
    }
    return _json({'results': [], 'latestSeq': 0});
  }

  static ResponseBody _json(Object body, [int status = 200]) => .fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
