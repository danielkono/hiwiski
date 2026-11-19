import 'package:drift/drift.dart' show Value;

import '../../core/api/generated/export.dart';
import '../../core/api/hiwiski_api.dart';
import '../../core/api/hiwiski_failure.dart';
import '../../core/common/ids.dart';
import '../../core/db/hiwiski_database.dart';
import '../query.dart';

/// Members, groups and invitations.
///
/// Over REST and not over the sync: they carry no share and no owner, so they are not
/// items in the sense of the glossary. Once the sync is in place, the client also
/// stores them locally — avatars and assignments must stay nameable offline
/// as well.
///
/// **Without a server** the family is the device's own table: the
/// member made here — in the demo, the family it shows. There are no groups and no
/// invitations.
class FamilyRepository {
  FamilyRepository(this._api, {required this._db, required this._serverless});

  final HiwiskiApi _api;
  final HiwiskiDatabase _db;
  final bool _serverless;

  late final _members = Query<String, List<Member>>(
    (_) => members(),
    keep: true,
  );
  late final _groups = Query<String, List<Group>>((_) => groups(), keep: true);
  late final _invitations = Query<String, List<Invitation>>(
    (_) => invitations(),
    keep: true,
  );

  /// The family's members, fetched once and shared — again after a change here.
  Stream<List<Member>> watchMembers() => _serverless
      ? _db
            .select(_db.members)
            .watch()
            .map((rows) => [for (final row in rows) row.toMember()])
      : _members.watch('');

  Stream<List<Group>> watchGroups() =>
      _serverless ? .value(const []) : _groups.watch('');

  Stream<List<Invitation>> watchInvitations() =>
      _serverless ? .value(const []) : _invitations.watch('');

  /// Fetches the family again — after a backup was restored under it.
  void refresh() {
    // Without a server the family is the device's table, and it tells by itself.
    if (_serverless) return;
    _members.refresh();
    _groups.refresh();
    _invitations.refresh();
  }

  Future<List<Member>> members() async => _serverless
      ? [for (final row in await _db.select(_db.members).get()) row.toMember()]
      : (await HiwiskiApi.run(() => _api.members.listMembers())).members;

  /// Adds a member to the device's own family — only without a server, where the
  /// device is the family: the demo's. Returns the new id.
  Future<String> addLocalMember(String displayName, String colorToken) async {
    if (!_serverless) {
      throw StateError('Members are added on the server when there is one.');
    }
    final id = newId();
    await _db
        .into(_db.members)
        .insert(
          MembersCompanion.insert(
            id: id,
            username: '',
            displayName: displayName,
            colorToken: Value(colorToken),
          ),
        );
    return id;
  }

  Future<PasswordReset> resetPassword(String memberId) =>
      HiwiskiApi.run(() => _api.members.resetMemberPassword(id: memberId));

  /// No sign-in and every device signed out, until [enable]; the member's things
  /// stay. The members are fetched again so the list shows it.
  Future<void> disable(String memberId) async {
    await HiwiskiApi.run(() => _api.members.disableMember(id: memberId));
    _members.refresh();
  }

  Future<void> enable(String memberId) async {
    await HiwiskiApi.run(() => _api.members.enableMember(id: memberId));
    _members.refresh();
  }

  /// Every device of the member loses access at once; they can sign in again.
  Future<void> signOutDevices(String memberId) =>
      HiwiskiApi.run(() => _api.members.signOutMember(id: memberId));

  Future<List<Group>> groups() async =>
      (await HiwiskiApi.run(() => _api.groups.listGroups())).groups;

  /// Creates the group, or changes the one with [id].
  /// A member's groups change with it: the members are fetched again too.
  Future<Group> saveGroup(WriteGroupRequest group, {String? id}) async {
    final saved = await HiwiskiApi.run(
      () => id == null
          ? _api.groups.createGroup(body: group)
          : _api.groups.updateGroup(id: id, body: group),
    );
    _groups.refresh();
    _members.refresh();
    return saved;
  }

  Future<void> deleteGroup(String id) async {
    await HiwiskiApi.run(() => _api.groups.deleteGroup(id: id));
    _groups.refresh();
  }

  Future<List<Invitation>> invitations() async =>
      (await HiwiskiApi.run(() => _api.invitations.listInvitations()))
          .invitations;

  Future<Invitation> createInvitation(
    CreateInvitationRequest invitation,
  ) async {
    final created = await HiwiskiApi.run(
      () => _api.invitations.createInvitation(body: invitation),
    );
    _invitations.refresh();
    return created;
  }

  /// Withdraws an invitation nobody has redeemed: its code opens nothing from now on.
  ///
  /// One the server no longer has open — redeemed or withdrawn on another device in
  /// the meantime — is not an error: either way it is no longer open, and the list
  /// fetched again shows what became of it.
  Future<void> revokeInvitation(String id) async {
    try {
      await HiwiskiApi.run(() => _api.invitations.revokeInvitation(id: id));
    } on HiwiskiFailure catch (failure) {
      if (failure.code != FailureCodes.identityInvitationNotFound) rethrow;
      // Redeemed in the meantime, it brought a new member along.
      _members.refresh();
    } finally {
      _invitations.refresh();
    }
  }

  /// Who an invitation code is for — before signing up with it.
  Future<InvitationPreview> previewInvitation(String code) =>
      HiwiskiApi.run(() => _api.invitations.previewInvitation(code: code));
}

extension on MemberRow {
  Member toMember() => .new(
    id: id,
    username: username,
    displayName: displayName,
    isAdmin: isAdmin,
    colorToken: ColorToken.fromJson(colorToken),
    avatarImageId: avatarImageId,
  );
}
