import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/repositories.dart';
import '../../app/stores.dart';
import '../../core/api/generated/export.dart';
import '../../domain/common/item_ref.dart';

part 'sharing_view_model.g.dart';

/// Who could be shared with: the family's members and groups.
@immutable
class const ShareDraftState({
  required final List<Member> members,
  required final List<Group> groups,

  /// Who is signed in — the owner of an item still to be created.
  final Member? me,
});

/// An item's share sheet, with the names its entries point to.
@immutable
class const SharingState({
  required final ShareSheet sheet,
  required final ShareDraftState directory,
});

@riverpod
Stream<List<Member>> _members(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchMembers();

@riverpod
Stream<List<Group>> _groups(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchGroups();

@riverpod
Stream<ShareSheet> _sheet(Ref ref, ItemRef item) =>
    ref.watch(accessRepositoryProvider).watchShareSheet(item);

/// Whether there is sharing at all. Without a server there is no one
/// to share with and no share sheet: every sharing row and section is left out —
/// not shown and refused.
@riverpod
class SharingAvailableViewModel extends _$SharingAvailableViewModel {
  @override
  bool build() => ref.watch(sessionProvider.select((s) => s.hasServer));
}

/// The share of an item that exists.
@riverpod
class SharingViewModel extends _$SharingViewModel {
  /// The sheet is waited for — offline, a refusal, or not on the server yet: the
  /// error says which. The names are not.
  @override
  Future<SharingState> build(ItemRef item) async {
    final members = ref.watch(_membersProvider).value ?? const <Member>[];
    final groups = ref.watch(_groupsProvider).value ?? const <Group>[];
    return SharingState(
      sheet: await ref.watch(_sheetProvider(item).future),
      directory: ShareDraftState(members: members, groups: groups),
    );
  }

  /// Writes the shares; the sheet shows what the server now sees.
  Future<void> setShares(List<WriteShare> shares) =>
      ref.read(accessRepositoryProvider).setShares(item, shares);

  /// Asks again — after the sheet could not be fetched.
  void retry() => ref.invalidate(_sheetProvider(item));
}

/// The share of an item still to be created — whom it could go to.
@riverpod
class ShareDraftViewModel extends _$ShareDraftViewModel {
  /// Whom it could go to is what the section is about: waited for, even from the
  /// server.
  @override
  Future<ShareDraftState> build() async {
    final me = ref.watch(sessionProvider.select((s) => s.member));
    final members = ref.watch(_membersProvider.future);
    final groups = ref.watch(_groupsProvider.future);
    return ShareDraftState(
      members: await members,
      groups: await groups,
      me: me,
    );
  }
}
