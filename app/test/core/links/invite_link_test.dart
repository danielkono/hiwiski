import 'package:hiwiski/domain/invite/invite_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads host and code from the invitation link', () {
    final link = parseInviteLink(
      'hiwiski://invite?host=hiwiski.local:8080&code=K7Q2M9X',
    );
    expect(link?.server.baseUrl, equals('http://hiwiski.local:8080'));
    expect(link?.code, equals('K7Q2M9X'));
  });

  test('keeps an explicit scheme', () {
    final link = parseInviteLink(
      'hiwiski://invite?host=https://hiwiski.example&code=ABC1234',
    );
    expect(link?.server.baseUrl, equals('https://hiwiski.example'));
  });

  // The server sends the scheme it was reached with,
  // percent-encoded, so a device joining a TLS server does not fall back to http.
  test('reads an encoded host with its scheme', () {
    final link = parseInviteLink(
      'hiwiski://invite?host=https%3A%2F%2Fnas.example%3A8443&code=ABC1234',
    );
    expect(link?.server.baseUrl, equals('https://nas.example:8443'));
    expect(link?.server.isCleartext, isFalse);
  });

  test('anything else is not an invitation link', () {
    expect(parseInviteLink('https://hiwiski.local/invitation?code=X'), isNull);
    expect(parseInviteLink('hiwiski://todo/123'), isNull);
    expect(parseInviteLink('hiwiski://invite?host=hiwiski.local'), isNull);
    expect(parseInviteLink('not a link'), isNull);
  });
}
