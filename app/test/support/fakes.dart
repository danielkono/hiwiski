import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/data/preferences/preferences_store.dart';
import 'package:hiwiski/data/family/family_repository.dart';
import 'package:hiwiski/data/session/session_repository.dart';
import 'package:hiwiski/data/session/session_store.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/storage/token_store.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:hiwiski/core/sync/sync_status.dart';
import 'package:hiwiski/components/sync_banner/sync_banner_view_model.dart';
import 'package:hiwiski/domain/links/link_index.dart';

/// Fakes several tests share — one copy, so that they do not drift apart.

/// A token store that holds nothing.
class NoTokens implements TokenStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<String?> readPersisted() => read();

  @override
  Future<void> write(String token, {bool persist = true}) async {}

  @override
  Future<void> clear() async {}
}

/// Anna, the administrator, signed in on device 1.
const signedInAnna = SessionState(
  stage: .signedIn,
  session: Session(
    member: Member(
      id: 'anna',
      username: 'anna',
      displayName: 'Anna',
      isAdmin: true,
      colorToken: .blue,
    ),
    deviceId: '00000000-0000-0000-0000-000000000001',
    mustChangePassword: false,
  ),
);

/// The session starts at [state] over the real providers — the repository, the
/// preferences and the sync come from the container.
Override sessionFrom(SessionState state) => sessionStoreProvider.overrideWith(
  (ref) => sessionStoreFor(ref, initial: state),
);

/// The session stands at [state] and needs nothing else: no server, no settings,
/// no sync — for the screens that only show who is signed in.
Override sessionAt(SessionState state, {SessionRepository? repository}) =>
    sessionStoreProvider.overrideWith((ref) {
      final store = SessionStore(
        repository: repository ?? _NoSessions(),
        preferences: _NoPreferences(),
        sync: _NoSync(),
        dropImages: () {},
        initial: state,
      );
      ref.onDispose(store.dispose);
      return store;
    });

class _NoSessions implements SessionRepository {
  /// A device that was never used without a server.
  @override
  Member? get localMember => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoPreferences extends ChangeNotifier implements PreferencesStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoSync implements SessionSync {
  @override
  Future<void> syncLast() async {}

  @override
  Future<void> stop() async {}
}

/// Online, nothing waiting, no conflict, no update: the sync banner every page shows
/// stays empty and needs no database or server.
final List<Override> quietSync = [
  syncStatusProvider.overrideWithValue(const SyncStatus()),
  servedWebAppProvider.overrideWithValue(false),
  syncBannerViewModelProvider.overrideWith(_QuietBanner.new),
];

class _QuietBanner extends SyncBannerViewModel {
  @override
  Future<SyncBannerState> build() async => SyncBannerState(
    status: const SyncStatus(),
    conflicts: const [],
    webUpdate: false,
    index: LinkIndex.from(const []),
    boards: const {},
  );
}

/// A family nobody is in yet: no members, no groups, no invitations — for the
/// screens that only name people.
class NoFamily implements FamilyRepository {
  @override
  Stream<List<Member>> watchMembers() => .value(const []);

  @override
  Stream<List<Group>> watchGroups() => .value(const []);

  @override
  Stream<List<Invitation>> watchInvitations() => .value(const []);

  @override
  void refresh() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
