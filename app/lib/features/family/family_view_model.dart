import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/repositories.dart';
import '../../app/stores.dart';
import '../../core/api/generated/export.dart' hide Mutation;
import '../../core/common/command.dart';

part 'family_view_model.g.dart';

/// `resetPassword`, run by a view: it shows the command running and reacts to how it ended.
final resetPasswordMutation = Mutation<PasswordReset>(
  label: 'familyViewModel.resetPassword',
);

/// `invite`, run by a view: it shows the command running and reacts to how it ended.
final inviteMutation = Mutation<Invitation>(label: 'familyViewModel.invite');

/// `saveGroup`, run by a view: it shows the command running and reacts to how it ended.
final saveGroupMutation = Mutation<Group>(label: 'familyViewModel.saveGroup');

/// The family: members, groups, open invitations.
@immutable
class const FamilyState({
  required final List<Member> members,
  required final List<Group> groups,

  /// Open invitations — the administrator's; empty for everyone else.
  required final List<Invitation> invitations,

  /// Only the administrator changes the family.
  required final bool isAdmin,
});

@riverpod
Stream<List<Member>> _members(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchMembers();

@riverpod
Stream<List<Group>> _groups(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchGroups();

@riverpod
Stream<List<Invitation>> _invitations(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchInvitations();

@riverpod
class FamilyViewModel extends _$FamilyViewModel {
  /// The family is what the screen is about: it is waited for, even from the
  /// server — offline the screen says so.
  @override
  Future<FamilyState> build() async {
    final isAdmin = ref.watch(sessionProvider.select((s) => s.isAdmin));
    final members = ref.watch(_membersProvider.future);
    final groups = ref.watch(_groupsProvider.future);
    final invitations = isAdmin ? ref.watch(_invitationsProvider.future) : null;
    return FamilyState(
      members: await members,
      groups: await groups,
      invitations: await invitations ?? const [],
      isAdmin: isAdmin,
    );
  }

  void retry() {
    ref
      ..invalidate(_membersProvider)
      ..invalidate(_groupsProvider)
      ..invalidate(_invitationsProvider);
  }

  /// Creates the group, or changes the one with [id].
  @command
  Future<Group> saveGroup(WriteGroupRequest group, {String? id}) =>
      ref.read(familyRepositoryProvider).saveGroup(group, id: id);

  Future<void> deleteGroup(String id) =>
      ref.read(familyRepositoryProvider).deleteGroup(id);

  @command
  Future<Invitation> invite(CreateInvitationRequest invitation) =>
      ref.read(familyRepositoryProvider).createInvitation(invitation);

  /// Withdraws an invitation nobody has redeemed: its code stops working.
  Future<void> revokeInvitation(Invitation invitation) =>
      ref.read(familyRepositoryProvider).revokeInvitation(invitation.id);

  @command
  Future<PasswordReset> resetPassword(Member member) =>
      ref.read(familyRepositoryProvider).resetPassword(member.id);

  /// Disables the member, or enables a disabled one again.
  Future<void> setDisabled(Member member, {required bool disabled}) => disabled
      ? ref.read(familyRepositoryProvider).disable(member.id)
      : ref.read(familyRepositoryProvider).enable(member.id);

  Future<void> signOutDevices(Member member) =>
      ref.read(familyRepositoryProvider).signOutDevices(member.id);
}
