import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/api/hiwiski_failure.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:hiwiski/data/session/session_repository.dart';

import '../support/fakes.dart';

/// **A changed password lets the member in**, whatever the follow-up handshake says.
/// A network failure there turned into "server unreachable" although the password was
/// set and the token valid.
void main() {
  test('a failing handshake after the change still signs in', () async {
    final repository = _FakeSessions();
    final container = ProviderContainer(
      overrides: [sessionAt(_mustChange, repository: repository)],
    );
    addTearDown(container.dispose);

    await container
        .read(sessionStoreProvider)
        .changePassword('old password', 'new password');
    await Future<void>.delayed(Duration.zero);

    final state = container.read(sessionProvider);
    expect(state.stage, equals(SessionStage.signedIn));
    expect(state.session?.mustChangePassword, isFalse);
    expect(repository.stored?.mustChangePassword, isFalse);
  });
}

const _member = Member(
  id: 'anna',
  username: 'anna',
  displayName: 'Anna',
  isAdmin: false,
  colorToken: .blue,
);

const _mustChange = SessionState(
  stage: .passwordChangeRequired,
  serverAddress: 'http://hiwiski.test',
  session: Session(member: _member, deviceId: 'd1', mustChangePassword: true),
);

class _FakeSessions implements SessionRepository {
  Session? stored;

  @override
  Future<void> changePassword(String current, String next) async {}

  @override
  Future<void> remember(Session? session, [Handshake? handshake]) async =>
      stored = session;

  @override
  Future<Handshake> handshake() async =>
      throw const HiwiskiFailure(code: FailureCodes.networkUnreachable);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
