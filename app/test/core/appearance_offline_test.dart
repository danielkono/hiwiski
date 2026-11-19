import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/api/hiwiski_failure.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/core/common/theme_preference.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:hiwiski/data/session/session_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

/// **The theme switch works offline** — and the choice is not lost. It threw
/// unhandled, nothing sent it again, and the next confirmation switched it back.
void main() {
  test('a theme chosen offline stays pending and goes out later', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    final sessions = _FakeSessions();
    final container = ProviderContainer(
      overrides: [
        localSettingsProvider.overrideWithValue(settings),
        sessionRepositoryProvider.overrideWithValue(sessions),
        sessionFrom(_signedIn),
      ],
    );
    addTearDown(container.dispose);
    final session = container.read(sessionStoreProvider);

    sessions.offline = true;
    await session.setTheme(ThemePreference.dark);

    expect(
      container.read(preferencesProvider).themeMode,
      equals(ThemePreference.dark),
    );
    expect(sessions.pending, isTrue);

    sessions.offline = false;
    await session.setTheme(ThemePreference.dark);
    expect(sessions.sent, equals(AppearanceMode.dark));
    expect(sessions.pending, isFalse);
  });
}

const _signedIn = SessionState(
  stage: .signedIn,
  serverAddress: 'http://hiwiski.test',
  session: Session(
    member: Member(
      id: 'anna',
      username: 'anna',
      displayName: 'Anna',
      isAdmin: false,
      colorToken: .blue,
    ),
    deviceId: 'd1',
    mustChangePassword: false,
  ),
);

class _FakeSessions implements SessionRepository {
  bool offline = false;
  bool pending = false;
  AppearanceMode? sent;

  @override
  bool get appearancePending => pending;

  @override
  Future<void> setAppearancePending(bool value) async => pending = value;

  @override
  Future<Member> updateMember(String id, UpdateMemberRequest change) async {
    if (offline) {
      throw const HiwiskiFailure(code: FailureCodes.networkUnreachable);
    }
    sent = change.appearance;
    return const Member(
      id: 'anna',
      username: 'anna',
      displayName: 'Anna',
      isAdmin: false,
      colorToken: .blue,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
