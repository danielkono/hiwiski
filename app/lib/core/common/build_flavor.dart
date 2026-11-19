/// What kind of build this is — decided when it is built, not at run time.
abstract final class BuildFlavor {
  /// The public demo: a web build that runs without a server, starts
  /// on sample data and keeps nothing — every page load begins anew. Built with
  /// `--dart-define=HIWISKI_DEMO=true`.
  static const demo = bool.fromEnvironment('HIWISKI_DEMO');

  /// The operator's legal notice and privacy policy for a build that has no server
  /// to name them — the demo. Relative addresses are read against the
  /// page's own, so the demo moves to another domain without a new build. Empty for
  /// every other build: there the server names them, or nobody does.
  static const legalNoticeUrl = String.fromEnvironment(
    'HIWISKI_LEGAL_NOTICE_URL',
  );
  static const privacyUrl = String.fromEnvironment('HIWISKI_PRIVACY_URL');

  /// Where the app's own privacy policy lies, for a build that keeps it elsewhere
  /// than `ProjectInfo.appPrivacyBase` — the demo, relative to itself. Empty: there.
  static const appPrivacyBase = String.fromEnvironment(
    'HIWISKI_APP_PRIVACY_BASE',
  );
}
