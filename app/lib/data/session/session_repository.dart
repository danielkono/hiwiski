import 'dart:convert';
import 'dart:typed_data';

import '../../core/api/generated/export.dart';
import '../../core/api/image_client.dart';
import '../../core/api/backup_file_client.dart';
import '../../core/api/hiwiski_api.dart';
import '../../core/common/ids.dart';
import '../../domain/common/server_address.dart';
import '../../core/platform/device_description.dart';
import '../../core/storage/local_image_store.dart';
import '../../core/storage/local_settings.dart';
import '../../core/storage/token_store.dart';
import 'local_data.dart';

/// A session this device confirmed before, with the handshake it came with.
typedef RememberedSession = ({Session session, Handshake? handshake});

/// The server, the sign-in and the device token.
///
/// Everything the session controller needs from below: the handshake, signing in and
/// out, the token, the remembered session for an offline start, and the data that
/// belongs to whoever is signed in ([LocalData]).
class SessionRepository {
  SessionRepository({
    required this._api,
    required this._tokens,
    required this._settings,
    required this._localData,
    required this._localImages,
  });

  // The remembered session, as JSON.
  static const _sessionKey = 'session';
  static const _handshakeKey = 'handshake';

  final HiwiskiApi _api;
  final TokenStore _tokens;
  final LocalSettings _settings;
  final LocalData _localData;
  final LocalImageStore _localImages;

  // --- The server ----------------------------------------------------------------

  /// The address of the server this device talks to — `null` before the first
  /// connection.
  String? get serverAddress => _settings.serverAddress;

  /// The address the client currently sends its calls to.
  String get baseUrl => _api.baseUrl;

  Future<Handshake> handshake() =>
      HiwiskiApi.run(() => _api.platform.getHandshake());

  /// Connects to a server and remembers the address — only once the server has
  /// answered; a server that does not answer leaves the previous address in place.
  Future<Handshake> connect(ServerAddress address) async {
    final previous = _api.baseUrl;
    _api.baseUrl = address.baseUrl;
    try {
      final handshake = await HiwiskiApi.run(
        () => _api.platform.getHandshake(),
      );
      await _settings.setServerAddress(address.baseUrl);
      return handshake;
    } catch (error) {
      _api.baseUrl = previous;
      rethrow;
    }
  }

  /// A different server, a different family: nothing from here belongs there, not
  /// even the queue.
  Future<void> forgetServer() async {
    await _localData.wipe();
    await _settings.setServerAddress(null);
    await _tokens.clear();
  }

  // --- Signing in and out --------------------------------------------------------

  Future<bool> hasToken() async {
    final token = await _tokens.read();
    return token != null && token.isNotEmpty;
  }

  Future<void> clearToken() => _tokens.clear();

  Future<Session> session() => HiwiskiApi.run(() => _api.auth.getSession());

  /// How this device introduces itself to the server.
  Future<DeviceRegistration> thisDevice({bool staySignedIn = true}) async {
    final device = await DeviceDescription.current();
    return DeviceRegistration(
      deviceName: device.name,
      platform: device.platform,
      staySignedIn: staySignedIn,
      installationId: await _settings.installationId(),
    );
  }

  Future<SignedIn> signIn(
    String username,
    String password, {
    required bool staySignedIn,
  }) async {
    final device = await thisDevice(staySignedIn: staySignedIn);
    return _adopt(
      await HiwiskiApi.run(
        () => _api.auth.login(
          body: LoginRequest(
            username: username,
            password: password,
            device: device,
          ),
        ),
      ),
      persist: staySignedIn,
    );
  }

  Future<SignedIn> runSetup(SetupRequest request) async =>
      _adopt(await HiwiskiApi.run(() => _api.setup.runSetup(body: request)));

  /// The setup code alone, before the wizard's steps: a wrong one is said at once.
  Future<void> checkSetupCode(String setupCode) => HiwiskiApi.run(
    () => _api.setup.checkSetupCode(body: SetupCodeCheck(setupCode: setupCode)),
  );

  /// Restoring on a fresh server: the archive goes up — with the setup code where the
  /// server asks for one — then its password opens the preview and the restore.
  Future<UploadedBackup> uploadSetupBackup(
    String? setupCode,
    Stream<List<int>> bytes,
    int length, {
    void Function(double done)? onProgress,
  }) => HiwiskiApi.run(
    () => _api.backupFiles.uploadForSetup(
      bytes,
      length,
      setupCode: setupCode,
      onProgress: onProgress == null
          ? null
          : (done, total) => onProgress(total <= 0 ? 0 : done / total),
    ),
  );

  Future<BackupPreview> inspectSetupBackup(
    String? setupCode,
    String id,
    String password,
  ) => HiwiskiApi.run(
    () => _api.setupRestore.inspectSetupBackup(
      xHiwiskiSetupCode: setupCode,
      id: id,
      body: BackupPasswordEntry(password: password),
    ),
  );

  Future<RestoreResult> restoreSetupBackup(
    String? setupCode,
    String id,
    String password,
  ) => HiwiskiApi.run(
    () => _api.setupRestore.restoreSetupBackup(
      xHiwiskiSetupCode: setupCode,
      id: id,
      body: BackupPasswordEntry(password: password),
    ),
  );

  Future<SignedIn> redeemInvitation(
    String code,
    RedeemInvitationRequest request,
  ) async => _adopt(
    await HiwiskiApi.run(
      () => _api.invitations.redeemInvitation(code: code, body: request),
    ),
  );

  /// Keeps the token of a fresh sign-in — without "Stay signed in" for this run of
  /// the app only.
  Future<SignedIn> _adopt(SignedIn signedIn, {bool persist = true}) async {
    await _tokens.write(signedIn.token, persist: persist);
    return signedIn;
  }

  Future<void> changePassword(String current, String next) => HiwiskiApi.run(
    () => _api.auth.changePassword(
      body: ChangePasswordRequest(currentPassword: current, newPassword: next),
    ),
  );

  /// Signs this device out on the server. The token stays — dropping it is the
  /// caller's decision, and it drops it even when the server is unreachable.
  Future<void> logout() => HiwiskiApi.run(() => _api.auth.logout());

  // --- The member ----------------------------------------------------------------

  /// A theme chosen offline, not yet on the server.
  bool get appearancePending => _settings.appearancePending;

  Future<void> setAppearancePending(bool value) =>
      _settings.setAppearancePending(value);

  Future<Member> updateMember(String memberId, UpdateMemberRequest change) =>
      HiwiskiApi.run(
        () => _api.members.updateMember(id: memberId, body: change),
      );

  /// One's own picture, uploaded with oneself as its carrier; returns its id.
  Future<String> uploadAvatar(
    String memberId,
    Uint8List bytes,
    String filename,
  ) => HiwiskiApi.run(
    () => _api.images.upload(
      ownerType: ImageOwnerTypes.member,
      ownerItemId: memberId,
      bytes: bytes,
      filename: filename,
    ),
  );

  /// One's own picture without a server: kept on the device until it connects.
  Future<String> keepAvatarLocally(
    String memberId,
    Uint8List bytes,
    String filename,
  ) => _localImages.put(
    ownerType: ImageOwnerTypes.member,
    ownerItemId: memberId,
    bytes: bytes,
    filename: filename,
  );

  // --- Without a server ---------------------------------------------

  /// The member this device made for itself, if it was started without a server and
  /// has not handed the member over to one yet.
  Member? get localMember {
    final json = _settings.localMember;
    if (json == null) return null;
    try {
      return Member.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// A new member for this device — an id of its own, which it keeps when it
  /// connects to a server later (`SetupAdmin.id`, `RedeemInvitationRequest.memberId`).
  /// The administrator of a family of one. Not kept yet: see [setLocalMember].
  static Member newLocalMember(String displayName) => .new(
    id: newId(),
    username: '',
    displayName: displayName,
    isAdmin: true,
    colorToken: .green,
  );

  /// Keeps the member made without a server — in the settings, for the next start,
  /// and in the device's family, where screens name it like any other member.
  Future<void> setLocalMember(Member? member) async {
    await _settings.setLocalMember(
      member == null ? null : jsonEncode(member.toJson()),
    );
    if (member != null) await _localData.keepMember(member);
  }

  /// The session of a member made without a server: no device on any server, and
  /// nothing to change first.
  static Session localSession(Member member) => .new(
    member: member,
    deviceId: LocalData.serverless,
    mustChangePassword: false,
  );

  /// The data on the device becomes the member's made without a server.
  Future<void> claimForLocal(String memberId) =>
      _localData.claimFor(memberId: memberId, server: LocalData.serverless);

  /// Compacts what waits in the outbox — on every start without a server.
  Future<void> compactLocal() => _localData.compactServerless();

  /// Back from a server the device was about to connect to: no address, no token —
  /// the member made without a server stays as it was.
  Future<void> leaveServer() async {
    await _settings.setServerAddress(null);
    await _tokens.clear();
    _api.baseUrl = '';
  }

  /// Whether the categories of the shopping list still have to go to the server
  /// the device connected to.
  Future<void> setCatalogCarryover(bool value) =>
      _settings.setCatalogCarryover(value);

  // --- What stays on the device --------------------------------------------------

  /// Remembers a confirmed session for the next start — only one that may work: a
  /// session that must change its password first has to get through to the server
  /// anyway.
  Future<void> remember(Session? session, [Handshake? handshake]) =>
      _settings.setLastSession(
        session == null || session.mustChangePassword
            ? null
            : jsonEncode({_sessionKey: session, _handshakeKey: handshake}),
      );

  /// The last confirmed session — `null` if there is none or it is unreadable (an
  /// older shape).
  RememberedSession? remembered() {
    final json = _settings.lastSession;
    if (json == null) return null;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final handshake = map[_handshakeKey];
      if (map[_sessionKey] case final Map<String, dynamic> session) {
        return (
          session: Session.fromJson(session),
          handshake: handshake == null
              ? null
              : Handshake.fromJson(handshake as Map<String, dynamic>),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// The data on the device belongs to the one whose session is starting now —
  /// **before** the first screen reads it.
  /// Returns whether someone else's data was cleared for it.
  Future<bool> claimLocalData(String memberId, {required String server}) =>
      _localData.claimFor(memberId: memberId, server: server);

  /// Everything that belongs to a member, off the device.
  Future<void> wipeLocalData() => _localData.wipe();

  /// Whether losing access clears the device at once instead of locking it — the
  /// member's choice in Account → Customize.
  bool get wipesOnAccessLost => _settings.wipeOnAccessLost;

  /// Keeps the session this device lost its access to — for the lock screen, after
  /// a restart too; `null` forgets it.
  Future<void> rememberLost(Session? session) =>
      _settings.setLostSession(session == null ? null : jsonEncode(session));

  /// The session this device lost its access to, if it did.
  Session? lostSession() {
    final json = _settings.lostSession;
    if (json == null) return null;
    try {
      return Session.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Whether anything of a member is on the device.
  Future<bool> holdsLocalData() => _localData.holdsData();
}
