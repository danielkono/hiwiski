import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/repositories.dart';
import '../../core/api/generated/export.dart';

part 'devices_view_model.g.dart';

@riverpod
Stream<List<Device>> _devices(Ref ref) =>
    ref.watch(deviceRepositoryProvider).watchDevices();

/// The member's signed-in devices.
@riverpod
class DevicesViewModel extends _$DevicesViewModel {
  @override
  Future<List<Device>> build() => ref.watch(_devicesProvider.future);

  /// Asks the server again — after the list could not be fetched.
  void retry() => ref.invalidate(_devicesProvider);

  /// Locks the device out at once: its token is dead from now on.
  Future<void> revoke(Device device) =>
      ref.read(deviceRepositoryProvider).revoke(device.id);
}
