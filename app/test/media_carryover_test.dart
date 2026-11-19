import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_image_store.dart';
import 'package:hiwiski/core/sync/outbox.dart';
import 'package:hiwiski/data/media/media_repository.dart';

import 'support/fakes.dart';

/// **An image added without a server is the only copy there is**: when
/// the server will not take it now, the device keeps it.
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

/// Answers every upload with [answer].
class _ImageServer implements HttpClientAdapter {
  (int, String) answer = (201, '');
  int uploads = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await requestStream?.drain<void>();
    uploads++;
    final (status, code) = answer;
    return .fromString(
      jsonEncode({'code': code}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
