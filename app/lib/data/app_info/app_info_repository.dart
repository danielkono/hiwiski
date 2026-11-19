import '../../core/platform/app_version.dart' as platform;

/// What the app knows about itself.
class AppInfoRepository {
  const AppInfoRepository();

  /// This build's version and build number — empty in a development build.
  Future<({String version, String build})> version() => platform.appVersion();
}
