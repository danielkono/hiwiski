import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/repositories.dart';
import '../../core/api/generated/export.dart';

part 'assignees_view_model.g.dart';

/// Who can be assigned: the family's members and its groups.
@immutable
class const AssigneesState({
  required final List<Member> members,
  required final List<Group> groups,
});

@riverpod
Stream<List<Member>> _members(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchMembers();

@riverpod
Stream<List<Group>> _groups(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchGroups();

@riverpod
class AssigneesViewModel extends _$AssigneesViewModel {
  /// Waited for, even from the server: still loading, or failed — offline, say —
  /// tells the picker apart from a family without anyone to assign.
  @override
  Future<AssigneesState> build() async {
    final members = ref.watch(_membersProvider.future);
    final groups = ref.watch(_groupsProvider.future);
    return AssigneesState(members: await members, groups: await groups);
  }
}
