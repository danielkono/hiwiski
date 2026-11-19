import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_token.dart';

/// Where the device token lives.
///
/// **The browser has no keychain.** `flutter_secure_storage` fakes one on this
/// platform but requires a secure context for it — and under `http://` that only
/// exists for `localhost`. The app could not be signed into from any other device on
/// the home network. So there the token lives in the browser's local storage; on the
/// home network it travels in plain text over the wire anyway, and the app points
/// that out.
///
/// **Without "Stay signed in" the token is not stored**: it lives for this run of the
/// app — in the browser for the tab — and a start without it is a session that ended.
abstract class TokenStore {
  Future<String?> read();

  /// The token only if it was stored to stay — not one held for this run of the app.
  /// The home screen widgets get only that one: without "Stay signed in" the session
  /// ends with the app, and so does what the home screen shows of it.
  Future<String?> readPersisted();

  /// [persist] `false`: for this run of the app only.
  Future<void> write(String token, {bool persist = true});

  Future<void> clear();

  static TokenStore create() => _SessionAwareTokenStore(
    kIsWeb ? _PreferencesTokenStore() : _SecureTokenStore(),
  );
}

/// The stored token, or the one held for this session only.
class _SessionAwareTokenStore implements TokenStore {
  _SessionAwareTokenStore(this._stored);

  final TokenStore _stored;

  @override
  Future<String?> read() async => readSessionToken() ?? await _stored.read();

  @override
  Future<String?> readPersisted() async =>
      readSessionToken() == null ? await _stored.read() : null;

  @override
  Future<void> write(String token, {bool persist = true}) async {
    if (persist) {
      writeSessionToken(null);
      await _stored.write(token);
    } else {
      // Nothing left behind for the next start.
      await _stored.clear();
      writeSessionToken(token);
    }
  }

  @override
  Future<void> clear() async {
    writeSessionToken(null);
    await _stored.clear();
  }
}

class _SecureTokenStore implements TokenStore {
  static const _key = 'hiwiski.device.token';
  // **Readable after the first unlock, not only while unlocked.** The background sync
  // runs with the phone in the pocket, locked — with the default the
  // keychain refuses the token exactly then. "This device only": the token belongs to
  // one device and has no business in a backup restored on another.
  //
  // **On macOS the classic login keychain**, not the data protection keychain: that
  // one needs the `keychain-access-groups` entitlement and with it a provisioning
  // profile, which an ad-hoc signed build does not have — writing the token failed
  // with a missing entitlement right after signing in. The login keychain encrypts
  // just as well and needs neither.
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: .first_unlock_this_device),
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<String?> readPersisted() => read();

  @override
  Future<void> write(String token, {bool persist = true}) =>
      _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class _PreferencesTokenStore implements TokenStore {
  static const _key = 'hiwiski.device.token';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<String?> readPersisted() => read();

  @override
  Future<void> write(String token, {bool persist = true}) async =>
      (await SharedPreferences.getInstance()).setString(_key, token);

  @override
  Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(_key);
}
