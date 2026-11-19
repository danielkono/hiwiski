import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/common/server_address.dart';

/// The home server's address as typed.
void main() {
  test('what is left out is filled in', () {
    final address = ServerAddress.parse('nas.local:8080')!;
    expect(address.baseUrl, equals('http://nas.local:8080'));
    expect(address.display, equals('nas.local:8080'));
  });

  // Behind a reverse proxy at a path, the path was dropped and every call went to
  // the proxy's root.
  test('a path is kept, without its trailing slash', () {
    final address = ServerAddress.parse('https://nas.local/hiwiski/')!;
    expect(address.baseUrl, equals('https://nas.local/hiwiski'));
    expect(address.display, equals('nas.local/hiwiski'));
  });
}
