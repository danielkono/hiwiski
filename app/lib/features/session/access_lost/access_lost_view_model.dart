import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../app/stores.dart';
import '../../../core/api/generated/export.dart' hide Mutation;

part 'access_lost_view_model.g.dart';

/// "Sign out and delete data", run by the lock screen: it keeps this ViewModel while
/// the screen is already gone.
final discardDataMutation = Mutation<void>(
  label: 'accessLostViewModel.discard',
);

/// The lock screen: whose data is locked on this device, and how many changes of
/// theirs are not on the server yet.
@immutable
class const AccessLostState({
  /// Whom the data belongs to; `null` where the device did not keep it.
  required final Member? member,

  /// Changes not yet synced — lost unless the same member signs in again.
  required final int pending,
});

@riverpod
Stream<int> _pending(Ref ref) =>
    ref.watch(syncRepositoryProvider).watchPendingCount();

@riverpod
class AccessLostViewModel extends _$AccessLostViewModel {
  @override
  Future<AccessLostState> build() async {
    final member = ref.watch(sessionProvider.select((s) => s.member));
    final pending = await ref.watch(_pendingProvider.future);
    return AccessLostState(member: member, pending: pending);
  }

  /// Clears the device: the data and the changes not yet synced are gone.
  Future<void> discard() =>
      ref.read(sessionStoreProvider).discardAfterAccessLost();
}
