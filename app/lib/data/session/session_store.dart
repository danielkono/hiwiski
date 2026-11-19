import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/backup_file_client.dart';
import '../../core/api/generated/export.dart';
import '../../core/api/hiwiski_failure.dart';
import '../../core/common/build_flavor.dart';
import '../../core/common/theme_preference.dart';
import '../../domain/common/server_address.dart';
import '../../domain/session/session_state.dart';
import '../preferences/preferences_store.dart';
import '../store.dart';
import 'session_repository.dart';

/// The sync as the session needs it: one last run before signing out, and a stop
/// before the device is cleared.
abstract interface class SessionSync {
  /// One run — after a background run that is under way, so it really is the last.
  Future<void> syncLast();

  Future<void> stop();
}

/// The session as a store, not as a stream from the database.
///
/// "State that survives a screen change belongs in a notifier. A stream only arrives
/// in the next cycle, and the screen that just saved asks for it right away — it would
/// get the old value."
class SessionStore extends Store<SessionState> {
  /// [initial] starts from a known value instead of the remembered session — for the
  /// tests.
  SessionStore({
    required this._repository,
    required this._preferences,
    required this._sync,
    required this._dropImages,
    SessionState? initial,
  }) : super(initial ?? _remembered(_repository)) {
    _followRestore();
  }

  final SessionRepository _repository;
  final PreferencesStore _preferences;
  final SessionSync _sync;

  /// A deliberate sign-out is under way — see [signOut].
  bool _signingOut = false;

  /// While a restore runs, the handshake is asked every few seconds until it is done
  /// — however the app learned of it: it started the restore, or it started while
  /// one ran.
  Timer? _restoreWatch;

  static const _restoreCheck = Duration(seconds: 3);

  @override
  @protected
  set value(SessionState next) {
    super.value = next;
    _followRestore();
  }

  void _followRestore() {
    if (value.restoring) {
      _restoreWatch ??= Timer.periodic(
        _restoreCheck,
        (_) => unawaited(checkRestore()),
      );
    } else {
      _restoreWatch?.cancel();
      _restoreWatch = null;
    }
  }

  /// This device starts a restore: it waits like every other at once, before the
  /// server's handshake says so.
  void beginRestore() => value = value.copyWith(restoreBegun: true);

  /// Asks the server whether the restore is still running.
  Future<void> checkRestore() async {
    try {
      final handshake = await _repository.handshake();
      value = value.copyWith(handshake: handshake, restoreBegun: false);
    } on Object catch (error) {
      // Unreachable for a moment: the next check asks again. Never the restore's
      // failure — the restore itself said how it went.
      debugPrint('hiwiski: restore check failed: $error');
    }
  }

  @override
  void dispose() {
    _restoreWatch?.cancel();
    super.dispose();
  }

  /// Throws the decoded images of whoever leaves out of memory.
  final VoidCallback _dropImages;

  static SessionState _remembered(SessionRepository repository) {
    final address = repository.serverAddress;
    // Used without a server: the member made here, and nothing to ask anyone. With an
    // address as well, the device is on its way to a server — the
    // handshake below decides where it goes on.
    // The demo always runs without a server, on a member of its own — the one from
    // the last visit, or a new one until the demo names it.
    if (BuildFlavor.demo) {
      return SessionState(
        stage: .localOnly,
        session: SessionRepository.localSession(
          repository.localMember ?? SessionRepository.newLocalMember(''),
        ),
      );
    }
    if (repository.localMember case final local? when address == null) {
      return SessionState(
        stage: .localOnly,
        session: SessionRepository.localSession(local),
      );
    }
    // **Whoever was signed in starts signed in** — on the last session the server
    // confirmed, not on the sign-in screen. Otherwise every start showed the sign-in
    // for the length of a handshake, and offline after a force quit the app could not
    // be used at all, although everything it needs is on the device. The handshake
    // below still decides: a revoked token signs out, a server that does not answer
    // changes nothing.
    // A device that lost its access stays locked until someone signs in again — a
    // restart does not open it.
    final lost = address == null ? null : repository.lostSession();
    if (lost != null) {
      return SessionState(
        stage: .accessLost,
        session: lost,
        serverAddress: address,
      );
    }
    final remembered = address == null ? null : repository.remembered();
    return remembered == null
        ? SessionState(
            stage: address == null
                ? SessionStage.noServer
                : SessionStage.unreachable,
            serverAddress: address,
          )
        : SessionState(
            stage: .signedIn,
            session: remembered.session,
            handshake: remembered.handshake,
            serverAddress: address,
          );
  }

  @visibleForTesting
  set debugValue(SessionState next) => value = next;

  /// Asks the server whether the remembered session still holds. Not for the
  /// background sync: it runs on the remembered session and learns from the sync
  /// itself whether the token still holds.
  void start() {
    if (value.stage == .localOnly) {
      // Not awaited, like the handshake below.
      unawaited(_compactLocal());
      return;
    }
    if (value.serverAddress == null) return;
    // **A start without a token ends what is left of the last session**:
    // a sign-in without "Stay signed in" keeps its token only for that run. Like any
    // loss of access this locks the device and keeps its data and unsynced changes,
    // so signing in again as the same member loses nothing; only "Delete everything
    // at once" in Account → Customize clears it here (`_endRevoked`).
    // **After** the provider is built, not inside it: `refresh()` changes the value,
    // and Riverpod forbids that while a provider is still being built. That is why in
    // the browser the app silently stayed on the sign-in screen even though the
    // server reported "not set up yet" — the exception only went to the console.
    //
    // Not awaited: the first frame should be up before the server has answered.
    Future.microtask(() async {
      await _endSessionWithoutToken();
      await refresh();
    }).ignore();
  }

  Future<void> _endSessionWithoutToken() async {
    if (_signingOut || value.stage == .accessLost) return;
    // On its way to a server: the data is the member's made without one, and no
    // token yet is the normal state until the server has taken them over.
    if (_repository.localMember != null) return;
    if (await _repository.hasToken()) return;
    if (!await _repository.holdsLocalData()) return;
    await _endRevoked();
  }

  /// Handshake, then session. In this order: without a handshake the app does not know
  /// whether the instance is set up at all, and a 401 on the session could not be
  /// interpreted.
  Future<void> refresh() async {
    // Without a server there is no one to ask — and a failed handshake would have
    // taken the device for one whose server is down.
    if (value.stage == .localOnly) return;
    value = value.copyWith(busy: true);
    try {
      final handshake = await _repository.handshake();
      if (!handshake.setupCompleted) {
        await _repository.remember(null);
        value = SessionState(
          stage: .setupRequired,
          handshake: handshake,
          serverAddress: value.serverAddress,
        );
        return;
      }
      if (!await _repository.hasToken()) {
        await _repository.remember(null);
        // Locked stays locked: only signing in again opens it.
        if (value.stage == .accessLost) {
          value = value.copyWith(handshake: handshake);
          return;
        }
        value = SessionState(
          stage: .signedOut,
          handshake: handshake,
          serverAddress: value.serverAddress,
        );
        return;
      }
      await _loadSession(handshake);
    } on HiwiskiFailure catch (failure) {
      if (failure.isUnauthorized) {
        // The token is gone or revoked. A revocation takes effect immediately, and
        // that is exactly why there is no JWT. Found on start, it locks the device
        // like a revocation noticed later: data and unsynced changes stay
        // until the member signs in again, and only "Delete everything at once" in
        // Account → Customize clears it (`_endRevoked`).
        await _endRevoked();
      } else if (value.stage != .signedIn && value.stage != .accessLost) {
        value = value.copyWith(stage: .unreachable, busy: false);
      }
      // Signed in and the server does not answer: offline, not signed out. The sync
      // retries on its own and signs out on a 401.
    } finally {
      value = value.copyWith(busy: false);
    }
  }

  Future<void> _loadSession(Handshake handshake) async {
    final session = await _repository.session();
    await _claimLocalData(session);
    await _repository.rememberLost(null);
    _applyAppearance(session);
    await _repository.remember(session, handshake);
    value = SessionState(
      stage: session.mustChangePassword
          ? SessionStage.passwordChangeRequired
          : SessionStage.signedIn,
      handshake: handshake,
      session: session,
      serverAddress: value.serverAddress,
    );
  }

  /// Connects to a server and remembers the address.
  ///
  /// Returns the handshake so the screen can show the family name and version as
  /// confirmation — without them nobody would know whether they reached the right
  /// server.
  ///
  /// A **different** server is a different family: the previous one is forgotten
  /// first — signed out there, the device cleared, the token gone. Otherwise the old
  /// server's token went out with the first request to the new address, and the old
  /// family's data stayed on the device until the next sign-in.
  Future<Handshake> connect(ServerAddress address) async {
    final previous = value.serverAddress;
    if (previous != null && previous != address.baseUrl) {
      // On the way from no server to one, the previous address only held a
      // handshake: the data is still the device's own and goes along.
      if (_repository.localMember != null) {
        await _repository.leaveServer();
      } else {
        await forgetServer();
      }
    }
    final handshake = await _repository.connect(address);
    value = SessionState(
      stage: handshake.setupCompleted
          ? SessionStage.signedOut
          : SessionStage.setupRequired,
      handshake: handshake,
      serverAddress: address.baseUrl,
    );
    await refresh();
    return handshake;
  }

  /// The local data becomes the current session's — for the sync, before it writes.
  /// Nothing happens while nobody is signed in, or when it is theirs already.
  Future<void> claimLocalData() async {
    final session = value.session;
    if (session != null) await _claimLocalData(session);
  }

  /// The data on the device belongs to the one whose session is starting now —
  /// **before** the first screen reads it.
  ///
  /// Clearing someone else's data also clears the remembered session and the cached
  /// images: the session that is staying is remembered again — otherwise the next
  /// start without network landed on "unreachable" instead of opening offline — and
  /// the decoded images of whoever left are dropped from memory.
  Future<void> _claimLocalData(Session session) async {
    final wiped = await _repository.claimLocalData(
      session.member.id,
      server: value.serverAddress ?? _repository.baseUrl,
    );
    await _finishTakeover();
    if (!wiped) return;
    _dropImages();
    if (value.session?.member.id == session.member.id) {
      await _repository.remember(value.session, value.handshake);
    }
  }

  // --- Without a server ---------------------------------------------

  /// Starts the app without a server: a member made on this device, owning
  /// everything that is made here.
  Future<void> startLocal(String displayName) async {
    final member = SessionRepository.newLocalMember(displayName);
    // Claimed first: whatever someone else left on the device goes, the family
    // table with it — the member is kept after that.
    await _repository.claimForLocal(member.id);
    await _repository.setLocalMember(member);
    value = SessionState(
      stage: .localOnly,
      session: SessionRepository.localSession(member),
    );
  }

  /// A compaction that fails changes nothing — the outbox stays as it was.
  Future<void> _compactLocal() async {
    try {
      await _repository.compactLocal();
    } on Object catch (error) {
      debugPrint('hiwiski: outbox not compacted: $error');
    }
  }

  /// The demo's member, under [displayName], owning the device's data — before the
  /// demo writes its sample data.
  Future<void> beginDemo(String displayName) async {
    final member = (value.member ?? SessionRepository.newLocalMember(''))
        .copyWith(displayName: displayName);
    await _repository.claimForLocal(member.id);
    await _repository.setLocalMember(member);
    value = SessionState(
      stage: .localOnly,
      session: SessionRepository.localSession(member),
    );
  }

  /// Everything made without a server goes; the member stays — the demo's reset.
  Future<void> clearLocalData() async {
    await _sync.stop();
    await _wipe();
  }

  /// Back from a server the device was about to connect to — before it has taken
  /// anything over. The member made here and their data stay as they were.
  Future<void> backToLocal() async {
    final local = _repository.localMember;
    if (local == null) return;
    await _repository.leaveServer();
    value = SessionState(
      stage: .localOnly,
      session: SessionRepository.localSession(local),
    );
  }

  /// Whether the device is on its way from no server to one: it has a member of its
  /// own that no server has taken over yet.
  bool get connectingFromLocal =>
      value.stage != .localOnly && _repository.localMember != null;

  /// The member made without a server, while the device connects — the setup and the
  /// invitation create them on the server under the same id.
  Member? get localMember => _repository.localMember;

  /// "Delete everything" without a server: the member made here and all their data,
  /// off the device. Afterwards it starts as if new.
  Future<void> discardLocal() async {
    value = const SessionState(stage: .noServer);
    await _sync.stop();
    await _wipe();
    await _repository.setLocalMember(null);
  }

  /// The server has taken the member made without one over: the device belongs to
  /// the server's member now. What does not go through the outbox — the shopping
  /// categories, the theme — goes out afterwards.
  Future<void> _finishTakeover() async {
    if (_repository.localMember == null) return;
    await _repository.setLocalMember(null);
    await _repository.setCatalogCarryover(true);
    await _repository.setAppearancePending(true);
  }

  /// Everything of whoever leaves, off the device — the cached images included.
  Future<void> _wipe() async {
    await _repository.wipeLocalData();
    _dropImages();
  }

  /// A different server, a different family: nothing from here belongs there.
  ///
  /// In the order of a sign-out: the session ends first, so no sync starts any more;
  /// the device is logged out, so it does not stay registered on the old server; a
  /// sync still running is stopped and waited for; only then is the device cleared.
  Future<void> forgetServer() async {
    final signedIn = value.member != null;
    value = const SessionState(stage: .noServer);
    if (signedIn) {
      try {
        await _repository.logout();
      } on HiwiskiFailure catch (failure) {
        // Unreachable: forgetting the server must not depend on it.
        debugPrint('hiwiski: logout not reported to the server: $failure');
      }
    }
    await _sync.stop();
    await _repository.forgetServer();
    _dropImages();
  }

  /// How this device introduces itself to the server — for the setup and for
  /// redeeming an invitation, which sign in on their own.
  Future<DeviceRegistration> thisDevice() => _repository.thisDevice();

  Future<void> signIn(
    String username,
    String password, {
    required bool staySignedIn,
  }) async => _adopt(
    await _repository.signIn(username, password, staySignedIn: staySignedIn),
  );

  /// A device used without a server brings its member: the administrator is created
  /// under the same id, and everything that names it stays valid.
  Future<void> runSetup(SetupRequest request) async {
    final local = connectingFromLocal ? _repository.localMember : null;
    await _adopt(
      await _repository.runSetup(
        local == null
            ? request
            : request.copyWith(admin: request.admin.copyWith(id: local.id)),
      ),
    );
  }

  /// Restoring an archive in place of the setup. Nobody is signed in by it: the
  /// members come from the archive, and the handshake after leads to the sign-in.
  Future<UploadedBackup> uploadSetupBackup(
    String setupCode,
    Stream<List<int>> bytes,
    int length, {
    void Function(double done)? onProgress,
  }) => _repository.uploadSetupBackup(
    setupCode,
    bytes,
    length,
    onProgress: onProgress,
  );

  Future<BackupPreview> inspectSetupBackup(
    String setupCode,
    String id,
    String password,
  ) => _repository.inspectSetupBackup(setupCode, id, password);

  Future<void> restoreSetupBackup(
    String setupCode,
    String id,
    String password,
  ) async {
    await _repository.restoreSetupBackup(setupCode, id, password);
    await refresh();
  }

  /// Like [runSetup]: a member made without a server joins under its own id.
  Future<void> redeemInvitation(
    String code,
    RedeemInvitationRequest request,
  ) async {
    final local = connectingFromLocal ? _repository.localMember : null;
    await _adopt(
      await _repository.redeemInvitation(
        code,
        local == null ? request : request.copyWith(memberId: local.id),
      ),
    );
  }

  /// Once changed, the member is in — whatever the follow-up handshake says. It was
  /// awaited from the "must change" stage, so a network failure there turned into
  /// "server unreachable" although the password was set and the token valid.
  Future<void> changePassword(String current, String next) async {
    await _repository.changePassword(current, next);
    final session = value.session;
    if (session != null) {
      final changed = session.copyWith(mustChangePassword: false);
      value = value.copyWith(stage: .signedIn, session: changed);
      await _repository.remember(changed, value.handshake);
    }
    // The handshake on its own: the password is changed already.
    refresh().ignore();
  }

  /// Signs this device out.
  ///
  /// The token is dropped locally even if the server is unreachable: whoever wants to
  /// sign out wants to sign out, and a device that stays signed in after the tap is a
  /// trap.
  ///
  /// Signing out **clears the device**: afterwards nothing of whoever left remains
  /// here — on a family computer someone else may well sign in next.
  ///
  /// Before that, one last sync so that changes still waiting are not lost — it waits
  /// for a run already under way and the one after it. Whatever is still waiting after
  /// that (offline) was named by the confirmation beforehand.
  Future<void> signOut() async {
    final sync = _sync;
    // From here on, a dead token is the member's own doing: the server answers the
    // logout by revoking it, and the sync run or the signal stream still open learns
    // that and reports "signed out elsewhere" — which locked the device with "Access
    // lost" right after a deliberate sign-out, so the member had to sign out twice.
    _signingOut = true;
    try {
      await _signOut(sync);
    } finally {
      _signingOut = false;
    }
  }

  Future<void> _signOut(SessionSync sync) async {
    try {
      await sync.syncLast();
    } on Object catch (failure) {
      // Offline, rejected, or broken on this side — the confirmation said what gets
      // lost then. Any failure: one that was not the server's used to stop the
      // sign-out itself, and the member could not sign out at all.
      debugPrint('hiwiski: last sync before sign-out failed: $failure');
    }
    try {
      await _repository.logout();
    } on HiwiskiFailure catch (failure) {
      // Signing out does not depend on the server -- see above.
      debugPrint('hiwiski: logout not reported to the server: $failure');
    }
    await _repository.clearToken();
    // End the session first, then clear: without a member no sync starts any more,
    // and one still running is stopped and waited for — otherwise its answers would
    // write the departed member's rows back into the cleared database.
    value = value.copyWith(stage: .signedOut, clearSession: true);
    await sync.stop();
    await _wipe();
  }

  /// This device was signed out elsewhere — in the device list of another one. The
  /// token is dead already; the device shows the sign-in at once instead of failing on
  /// every call. It is locked, not cleared: its data and unsynced changes
  /// stay until the member signs in again, unless they chose "Delete everything at
  /// once" (`_endRevoked`).
  Future<void> signedOutElsewhere() async {
    if (_signingOut) return;
    if (value.member == null || value.stage == .accessLost) return;
    await _endRevoked();
  }

  /// The token is dead — revoked, expired, or a session that ended with the app.
  ///
  /// **The device is locked, not cleared** (unless the member chose to clear it in
  /// Account → Customize): its data and the changes not yet synced stay, the lock
  /// screen says so, and whoever signs in again as the same member keeps them. It
  /// used to be cleared, and changes made offline were lost with it.
  Future<void> _endRevoked() async {
    await _repository.clearToken();
    await _repository.remember(null);
    if (_repository.wipesOnAccessLost) {
      value = value.copyWith(
        stage: .signedOut,
        busy: false,
        clearSession: true,
      );
      await _sync.stop();
      await _wipe();
      return;
    }
    await _repository.rememberLost(value.session);
    value = value.copyWith(stage: .accessLost, busy: false);
    await _sync.stop();
  }

  /// "Sign out and delete data" on the lock screen: the device cleared, as signing
  /// out clears it — the changes not yet synced are lost.
  Future<void> discardAfterAccessLost() async {
    value = SessionState(
      stage: .signedOut,
      handshake: value.handshake,
      serverAddress: value.serverAddress,
    );
    await _sync.stop();
    await _wipe();
  }

  /// The last sync before signing out, on its own — so the confirmation can say what
  /// is still waiting **after** it. A failure (offline) is no reason not to ask.
  Future<void> syncBeforeSignOut() async {
    try {
      await _sync.syncLast();
    } on Object catch (failure) {
      debugPrint('hiwiski: sync before sign-out failed: $failure');
    }
  }

  /// The choice belongs to the member, not the device, and is synced along; it is also
  /// kept locally so the first frame after startup is already right.
  ///
  /// Local first, then on the server: the switch should flip immediately, even when
  /// the home server is unreachable at the moment.
  Future<void> setTheme(ThemePreference mode) async {
    await _preferences.setThemeMode(mode);
    await _repository.setAppearancePending(true);
    await _sendAppearance();
  }

  /// Sends the theme chosen here to the server. Offline it stays pending — the switch
  /// works offline as promised — and goes out with the next confirmation. It used to
  /// throw unhandled, nothing sent it again, and the next confirmation switched the
  /// theme back to the server's old one.
  Future<void> _sendAppearance() async {
    final member = value.member;
    // Without a server it waits, as offline, for the one the device connects to.
    if (member == null || value.stage == .localOnly) return;
    if (!_repository.appearancePending) return;
    final mode = _preferences.value.themeMode;
    try {
      await _repository.updateMember(
        member.id,
        UpdateMemberRequest(
          appearance: switch (mode) {
            .light => AppearanceMode.light,
            .dark => AppearanceMode.dark,
            .system => AppearanceMode.system,
          },
        ),
      );
      await _repository.setAppearancePending(false);
    } on HiwiskiFailure catch (failure) {
      // Offline: later. Anything else would be refused the next time too.
      if (!failure.isNetwork) await _repository.setAppearancePending(false);
    }
  }

  /// Changes one's own profile — the name others see, the picture — and takes the
  /// answer over at once, so the header and the account show it without a reload.
  Future<void> updateProfile({
    String? displayName,
    String? avatarImageId,
    bool removeAvatar = false,
  }) async {
    final member = value.member;
    final session = value.session;
    if (member == null || session == null) return;
    if (value.stage == .localOnly) {
      final changed = member.copyWith(
        displayName: displayName ?? member.displayName,
        avatarImageId: removeAvatar
            ? null
            : avatarImageId ?? member.avatarImageId,
      );
      await _repository.setLocalMember(changed);
      value = value.copyWith(session: session.copyWith(member: changed));
      return;
    }
    final updated = await _repository.updateMember(
      member.id,
      UpdateMemberRequest(
        displayName: displayName,
        avatarImageId: avatarImageId,
        removeAvatar: removeAvatar ? true : null,
      ),
    );
    value = value.copyWith(session: session.copyWith(member: updated));
    await _repository.remember(value.session, value.handshake);
  }

  /// One's own picture: uploaded with oneself as its carrier, then set on the profile.
  Future<void> uploadAvatar(Uint8List bytes, String filename) async {
    final member = value.member;
    if (member == null) return;
    final id = value.stage == .localOnly
        ? await _repository.keepAvatarLocally(member.id, bytes, filename)
        : await _repository.uploadAvatar(member.id, bytes, filename);
    await updateProfile(avatarImageId: id);
  }

  /// What is on the server wins: the theme choice belongs to the member and follows
  /// them to every device.
  void _applyAppearance(Session session) {
    // A choice made here that has not gone out yet wins — and goes out now.
    if (_repository.appearancePending) {
      // Stays pending and goes out with the next session refresh.
      _sendAppearance().ignore();
      return;
    }
    final appearance = session.appearance;
    if (appearance == null) return;
    // Only the local copy of the theme; the server has it.
    _preferences.setThemeMode(switch (appearance) {
      .light => ThemePreference.light,
      .dark => ThemePreference.dark,
      _ => ThemePreference.system,
    }).ignore();
  }

  Future<void> _adopt(SignedIn signedIn) async {
    // Someone else than the locked member clears the device here; the same member
    // keeps it, and their waiting changes go out.
    await _claimLocalData(signedIn.session);
    await _repository.rememberLost(null);
    _applyAppearance(signedIn.session);
    await _repository.remember(signedIn.session, value.handshake);
    value = value.copyWith(
      stage: signedIn.session.mustChangePassword
          ? SessionStage.passwordChangeRequired
          : SessionStage.signedIn,
      session: signedIn.session,
    );
  }
}
