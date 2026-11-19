import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/repositories.dart';
import '../../app/stores.dart';
import '../../core/api/generated/export.dart';
import '../../domain/common/server_address.dart';

part 'redeem_invitation_view_model.g.dart';

/// What the redeem screen shows besides the code.
@immutable
class const RedeemInvitationState({
  /// The connection runs in plain text: the password chosen here goes over the
  /// wire readable, and the screen says so before it is typed.
  required final bool cleartext,

  /// The address the app is connected to, for reading — the host, and the port
  /// where there is one. The code goes there, and so do the name and the password
  /// chosen here.
  required final String? serverDisplay,
});

/// "Redeem invitation": who a code is for, and joining with it.
@riverpod
class RedeemInvitationViewModel extends _$RedeemInvitationViewModel {
  @override
  RedeemInvitationState build() {
    final session = ref.watch(sessionProvider);
    return .new(
      cleartext: session.isCleartext,
      serverDisplay: ServerAddress.parse(session.serverAddress ?? '')?.display,
    );
  }

  /// [request] gets how this device introduces itself to the server.
  Future<void> join(
    String code,
    RedeemInvitationRequest Function(DeviceRegistration device) request,
  ) async {
    final session = ref.read(sessionStoreProvider);
    final device = await session.thisDevice();
    await session.redeemInvitation(code, request(device));
  }
}

/// Who an invitation code is for — before signing up with it. Keyed by the code: an
/// answer for a code typed over since is never shown.
@riverpod
class InvitationPreviewViewModel extends _$InvitationPreviewViewModel {
  @override
  Future<InvitationPreview> build(String code) =>
      ref.watch(familyRepositoryProvider).previewInvitation(code);
}
