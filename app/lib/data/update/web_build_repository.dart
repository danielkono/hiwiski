import '../../core/platform/web_build.dart' as platform;

/// Which build of the web app the server serves, and the way to it.
class WebBuildRepository {
  const WebBuildRepository();

  /// The served build's id — `null` outside the browser, offline, or when the server
  /// does not say.
  Future<String?> served() => platform.fetchServedBuild();

  void reload() => platform.reloadPage();
}
