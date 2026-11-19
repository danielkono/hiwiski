import 'package:web/web.dart' as web;

const _key = 'hiwiski.session.token';

/// A token for this browser tab: it survives a reload and ends with the tab — the
/// browser's own idea of a session.
String? readSessionToken() => web.window.sessionStorage.getItem(_key);

void writeSessionToken(String? token) {
  if (token == null) {
    web.window.sessionStorage.removeItem(_key);
  } else {
    web.window.sessionStorage.setItem(_key, token);
  }
}
