import 'package:package_info_plus/package_info_plus.dart';

/// The version this build carries and its build number.
///
/// The release lanes set both with `--build-name` and `--build-number`;
/// a development build has neither, and `pubspec.yaml` holds no
/// version — then both are empty.
Future<({String version, String build})> appVersion() async {
  final info = await PackageInfo.fromPlatform();
  return (version: info.version, build: info.buildNumber);
}
