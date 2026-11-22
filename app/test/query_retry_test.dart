import 'package:dio/dio.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/api/hiwiski_failure.dart';
import 'package:hiwiski/data/media/media_repository.dart';
import 'package:hiwiski/data/query.dart';

/// A watched answer that failed is asked for again — a picture another device
/// uploads only after its element arrived here was shown as failed until a reload.
void main() {
  test('a failure is tried again while watched, the watcher waiting', () async {
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
    // No failure on the way: the answer once it came.
    expect(seen, equals([42]));
  });

  test('once the tries give up, the watcher hears of the failure', () async {
    final query = Query<String, int>(
      (_) async => throw const HiwiskiFailure(code: 'gone'),
      retryAfter: (_, tries) => tries <= 2 ? Duration.zero : null,
    );
    final seen = <Object>[];
    final watching = query.watch('a').listen(seen.add, onError: seen.add);
    addTearDown(watching.cancel);

    await pumpEventQueue();

    expect(seen.single, isA<HiwiskiFailure>());
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
