import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../api/generated/export.dart';
import '../common/app_names.dart';

/// What this device is called and what it is.
///
/// The name shows up in the device list and is read when locking a device out — "Anna's
/// iPhone" is useful there, "Device 3" is not.
class DeviceDescription {
  const DeviceDescription(this.name, this.platform);

  final String name;
  final DevicePlatform platform;

  static const _browser = 'Browser';

  static Future<DeviceDescription> current() async {
    final info = DeviceInfoPlugin();
    if (kIsWeb) {
      final web = await info.webBrowserInfo;
      return DeviceDescription(
        '${web.browserName.name} · $_browser',
        DevicePlatform.web,
      );
    }
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      return DeviceDescription(android.model, DevicePlatform.android);
    }
    if (Platform.isIOS) {
      final ios = await info.iosInfo;
      return DeviceDescription(ios.name, DevicePlatform.ios);
    }
    if (Platform.isMacOS) {
      final mac = await info.macOsInfo;
      return DeviceDescription(mac.computerName, DevicePlatform.macos);
    }
    if (Platform.isWindows) {
      final windows = await info.windowsInfo;
      return DeviceDescription(windows.computerName, DevicePlatform.windows);
    }
    if (Platform.isLinux) {
      final linux = await info.linuxInfo;
      return DeviceDescription(linux.prettyName, DevicePlatform.linux);
    }
    return const DeviceDescription(AppNames.product, DevicePlatform.unknown);
  }
}
