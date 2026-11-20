import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_image_store.dart';
import 'package:hiwiski/core/sync/outbox.dart';
import 'package:hiwiski/data/media/media_repository.dart';

import 'support/fakes.dart';

/// **An image kept on the device is the only copy there is** — added without a
/// server, or to a text, which goes up with the sync: it goes up once its carrier is
/// on the server, and when the server will not take it now, the device keeps it.
void main() {
  late HiwiskiDatabase db;
  late LocalImageStore localImages;
  late _ImageServer server;
  late MediaRepository media;
  final bytes = Uint8List.fromList([1, 2, 3]);

  setUp(() {
    db = HiwiskiDatabase(NativeDatabase.memory());
    localImages = LocalImageStore(db);
    server = _ImageServer();
    final api = HiwiskiApi(tokens: NoTokens(), baseUrl: 'http://hiwiski.test');
    api.dio.httpClientAdapter = server;
    media = MediaRepository(
      api,
      localImages: localImages,
      outbox: Outbox(db),
      serverless: false,
    );
  });

  tearDown(() => db.close());

  Future<String> keep() => localImages.put(
    ownerType: 'WIKI_PAGE',
    ownerItemId: 'page',
    bytes: bytes,
    filename: 'a.png',
  );

  test('it waits while its carrier waits in the outbox, then goes up as itself', () async {
    final id = await keep();
    // The page's text, naming the image, has not gone out yet: the server would
    // not know the page.
    await db
        .into(db.outboxEntries)
        .insert(
          OutboxEntriesCompanion.insert(
            mutationId: 'm1',
            entityType: EntityTypes.wikiPage,
            entityId: 'page',
            op: SyncOps.upsert,
            createdAt: DateTime(2026, 11, 20),
          ),
        );

    expect(await media.carryOver(), isEmpty);
    expect(server.uploads, equals(0));

    await db.delete(db.outboxEntries).go();
    final uploaded = await media.carryOver();

    expect(uploaded.map((image) => image.id), equals([id]));
    expect(server.ids, equals([id]));
    expect(await localImages.read(id), isNull);
  });

  // After a sync and before signing out, both at once: each image goes up once.
  test('two runs side by side upload each image once', () async {
    final id = await keep();

    final runs = await Future.wait([media.carryOver(), media.carryOver()]);

    expect(server.ids, equals([id]));
    expect(runs.first.map((image) => image.id), equals([id]));
    expect(runs.last.map((image) => image.id), equals([id]));
  });

  test('past the quota, the image stays and is not sent again', () async {
    final id = await keep();
    server.answer = (413, 'media.quota_exceeded');

    expect(await media.carryOver(), isEmpty);
    expect(await media.carryOver(), isEmpty);

    expect(server.uploads, equals(1));
    expect(await localImages.read(id), equals(bytes));
    expect(await media.image(id, preview: false), equals(bytes));
  });

  test('under an id already taken, the only copy stays', () async {
    final id = await keep();
    server.answer = (409, 'media.id_taken');

    expect(await media.carryOver(), isEmpty);
    expect(await media.carryOver(), isEmpty);

    expect(server.uploads, equals(1));
    expect(await media.image(id, preview: true), equals(bytes));
  });

  test('a carrier the server does not know gives the image up', () async {
    final id = await keep();
    server.answer = (404, 'media.owner_not_found');

    expect(await media.carryOver(), isEmpty);

    expect(await localImages.read(id), isNull);
  });
}

/// Answers every upload with [answer] — a success with the id it was sent.
class _ImageServer implements HttpClientAdapter {
  (int, String) answer = (201, '');
  int get uploads => ids.length;

  /// The ids the uploads were sent under, in order.
  final ids = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await requestStream?.drain<void>();
    final form = options.data as FormData;
    final id = form.fields
        .where((field) => field.key == 'id')
        .map((field) => field.value)
        .firstOrNull;
    ids.add(id);
    final (status, code) = answer;
    return .fromString(
      jsonEncode(status == 201 ? {'id': id} : {'code': code}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
