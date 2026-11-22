import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/api/hiwiski_failure.dart';

/// **A proxy in front of a server that is down means offline, not "server error".**
void main() {
  DioException answered(int status, Object? body) {
    final request = RequestOptions(path: '/api/v1/sync/pull');
    return DioException.badResponse(
      statusCode: status,
      requestOptions: request,
      response: Response(
        requestOptions: request,
        statusCode: status,
        data: body,
      ),
    );
  }

  test("a gateway's own error page is offline", () {
    for (final status in [502, 503, 504]) {
      expect(
        HiwiskiFailure.from(answered(status, '<html>Bad Gateway</html>'))
            .isNetwork,
        isTrue,
        reason: '$status',
      );
    }
  });

  test('an error the server itself wrote stays that error', () {
    final failure = HiwiskiFailure.from(
      answered(503, {'code': 'server.maintenance'}),
    );
    expect(failure.isNetwork, isFalse);
    expect(failure.code, equals('server.maintenance'));
  });

  test('a 500 without a body stays a server error', () {
    expect(HiwiskiFailure.from(answered(500, null)).isNetwork, isFalse);
  });

  test('an error answered as bytes keeps its code', () {
    // An image is fetched as bytes, and so is its error.
    final failure = HiwiskiFailure.from(
      answered(
        404,
        utf8.encode(
          '{"code":"media.image_not_found","params":{"id":"x"},'
          '"correlationId":"c1"}',
        ),
      ),
    );
    expect(failure.code, equals('media.image_not_found'));
    expect(failure.status, equals(404));
    expect(failure.correlationId, equals('c1'));
    // Bytes that are no error body leave a server error.
    expect(
      HiwiskiFailure.from(answered(500, [0xff, 0xd8, 0xff])).code,
      equals(FailureCodes.serverError),
    );
  });
}
