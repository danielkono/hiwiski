import '../../core/api/generated/export.dart';
import '../../core/api/hiwiski_api.dart';
import '../query.dart';

/// The signed-in devices of the member — over REST.
class DeviceRepository {
  DeviceRepository(this._api);

  final HiwiskiApi _api;

  late final _devices = Query<String, List<Device>>(
    (_) => devices(),
    keep: true,
  );

  Stream<List<Device>> watchDevices() => _devices.watch('');

  Future<List<Device>> devices() async =>
      (await HiwiskiApi.run(() => _api.devices.listDevices())).devices;

  /// Locks the device out at once: its token is dead from now on.
  Future<void> revoke(String id) async {
    await HiwiskiApi.run(() => _api.devices.revokeDevice(id: id));
    _devices.refresh();
  }
}
