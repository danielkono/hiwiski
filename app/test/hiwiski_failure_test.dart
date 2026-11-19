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
}
