import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/components/rich_text/view/rich_image.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/api/hiwiski_failure.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_image_store.dart';
import 'package:hiwiski/core/sync/outbox.dart';
import 'package:hiwiski/core/theme/hiwiski_symbols.dart';
import 'package:hiwiski/data/media/media_repository.dart';
import 'package:hiwiski/data/query.dart';

import 'support/fakes.dart';

/// A watched answer that failed is asked for again — a picture another device
/// uploads only after its element arrived here was shown as failed until a reload.
void main() {
  test('a failure is told at once and tried again while watched', () async {
    int asked = 0;
    final query = Query<String, int>((_) async {
      asked++;
      if (asked < 3) throw const HiwiskiFailure(code: 'not.yet');
      return 42;
    }, retryAfter: (_, tries) => tries <= 5 ? Duration.zero : null);
    final seen = <Object>[];
    final watching = query.watch('a').listen(seen.add, onError: seen.add);
    addTearDown(watching.cancel);

    await pumpEventQueue();

    expect(asked, equals(3));
    // Each failure as it came, then the answer in its place.
    expect(seen, hasLength(3));
    expect(seen.take(2), everyElement(isA<HiwiskiFailure>()));
    expect(seen.last, equals(42));
  });

  testWidgets('an image not there yet says so, and shows once it comes', (
    tester,
  ) async {
    final media = _Media();
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        overrides: [mediaRepositoryProvider.overrideWithValue(media)],
        child: const Directionality(
          textDirection: .ltr,
          child: RichImage(imageId: 'picture'),
        ),
      ),
    );
    await tester.pump();

    // Not a spinner for the minutes the tries take: the failure, at once.
    expect(find.byIcon(HiwiskiSymbols.errorOutline), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    media.uploaded = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(media.asked, equals(2));
    expect(find.byIcon(HiwiskiSymbols.errorOutline), findsNothing);
    expect(find.byType(RawImage), findsOneWidget);
  });

  test('once the tries give up, nothing more is asked for', () async {
    int asked = 0;
    final query = Query<String, int>((_) async {
      asked++;
      throw const HiwiskiFailure(code: 'gone');
    }, retryAfter: (_, tries) => tries <= 2 ? Duration.zero : null);
    final seen = <Object>[];
    final watching = query.watch('a').listen(seen.add, onError: seen.add);
    addTearDown(watching.cancel);

    await pumpEventQueue();

    expect(asked, equals(3));
    expect(seen, hasLength(3));
    expect(seen, everyElement(isA<HiwiskiFailure>()));
  });

  test('nobody watching, nothing is asked for again', () async {
    int asked = 0;
    final query = Query<String, int>((_) async {
      asked++;
      throw const HiwiskiFailure(code: 'not.yet');
    }, retryAfter: (_, _) => Duration.zero);
    final watching = query.watch('a').listen((_) {}, onError: (_) {});
    await watching.cancel();

    await pumpEventQueue();

    expect(asked, lessThanOrEqualTo(1));
  });

  test('an image is asked for again while it may still come', () {
    const missing = HiwiskiFailure(
      code: FailureCodes.mediaImageNotFound,
      status: 404,
    );
    final waits = [
      for (int tries = 1; tries <= 8; tries++) imageRetryAfter(missing, tries),
    ];
    // Ever less often, up to a while between two.
    expect(waits.first, equals(const Duration(seconds: 1)));
    expect(waits.last, equals(const Duration(seconds: 30)));
    expect(imageRetryAfter(missing, 13), isNull);
    expect(imageRetryAfter(const HiwiskiFailure.network(), 1), isNotNull);
    expect(
      imageRetryAfter(const HiwiskiFailure(code: 'server', status: 503), 1),
      isNotNull,
    );
    // As it really comes: the image endpoint answers with bytes, its error too.
    final request = RequestOptions(path: '/api/v1/images/x');
    final notUploadedYet = DioException.badResponse(
      statusCode: 404,
      requestOptions: request,
      response: Response(
        requestOptions: request,
        statusCode: 404,
        data: utf8.encode('{"code":"media.image_not_found"}'),
      ),
    );
    expect(imageRetryAfter(notUploadedYet, 1), isNotNull);
    // Not allowed to see it: no use asking again.
    expect(
      imageRetryAfter(const HiwiskiFailure(code: 'forbidden', status: 403), 1),
      isNull,
    );
  });
}

/// A picture the server has only once it is [uploaded].
class _Media extends MediaRepository {
  _Media()
    : super(
        HiwiskiApi(tokens: NoTokens(), baseUrl: 'http://hiwiski.test'),
        localImages: LocalImageStore(_unused),
        outbox: Outbox(_unused),
        serverless: false,
      );

  /// Never opened: the fake answers every image itself.
  static final _unused = HiwiskiDatabase(NativeDatabase.memory());

  bool uploaded = false;
  int asked = 0;

  @override
  Future<Uint8List> image(String id, {required bool preview}) async {
    asked++;
    if (!uploaded) {
      throw const HiwiskiFailure(
        code: FailureCodes.mediaImageNotFound,
        status: 404,
      );
    }
    return _pixel;
  }
}

/// A 1×1 transparent PNG.
final _pixel = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
