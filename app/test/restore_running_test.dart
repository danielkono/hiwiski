import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/data/preferences/preferences_store.dart';
import 'package:hiwiski/data/session/session_repository.dart';
import 'package:hiwiski/data/session/session_store.dart';
import 'package:hiwiski/domain/session/session_state.dart';

/// **A restore is visible wherever the app is** — on the device that started it at
/// once, and on one started again meanwhile from the handshake; and it ends by itself
/// once the server says so.
void main() {
  test('this device waits from the moment it starts the restore', () async {
    final server = _Server(restoring: true);
    final store = _store(server, restoring: false);
    addTearDown(store.dispose);

    store.beginRestore();
    expect(store.value.restoring, isTrue);

    server.restoring = false;
    await store.checkRestore();
    expect(store.value.restoring, isFalse);
  });

  // On the test clock: the store asks every three seconds.
  testWidgets('an app started while a restore runs asks until it is done', (
    tester,
  ) async {
    final server = _Server(restoring: true);
    final store = _store(server, restoring: true);
    expect(store.value.restoring, isTrue);

    await tester.pump(const Duration(seconds: 4));
    expect(server.asked, greaterThanOrEqualTo(1));
    expect(store.value.restoring, isTrue);

    server.restoring = false;
    await tester.pump(const Duration(seconds: 4));
    expect(store.value.restoring, isFalse);
    final asked = server.asked;
    await tester.pump(const Duration(seconds: 4));
    expect(server.asked, equals(asked), reason: 'done: no more asking');
    store.dispose();
  });
}

SessionStore _store(_Server server, {required bool restoring}) => .new(
  repository: server,
  preferences: _NoPreferences(),
  sync: _NoSync(),
  dropImages: () {},
  initial: SessionState(
    stage: .signedIn,
    handshake: _handshake(restoring: restoring),
  ),
);

Handshake _handshake({required bool restoring}) => .new(
  apiVersion: 'v1',
  serverVersion: '2026.1.0',
  minClientVersion: '2026.1.0',
  setupCompleted: true,
  cleartext: false,
  restoring: restoring ? true : null,
);

class _Server implements SessionRepository {
  _Server({required this.restoring});

  bool restoring;
  int asked = 0;

  @override
  Future<Handshake> handshake() async {
    asked++;
    return _handshake(restoring: restoring);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoPreferences implements PreferencesStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoSync implements SessionSync {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
