/// The names the app goes by where no translation reaches: URI schemes, file names,
/// the fallback for a missing name.
abstract final class AppNames {
  /// The product, lower case as it appears in addresses and file names.
  static const product = 'hiwiski';
}

/// The URI schemes the app reads or writes.
abstract final class UriSchemes {
  static const http = 'http';
  static const https = 'https';
  static const mailto = 'mailto';

  /// Links between items and invitations: `hiwiski://todo/<uuid>`.
  static const hiwiski = AppNames.product;

  /// An image in a wiki page's text: `![](hiwiski-image:<uuid>)`.
  static const hiwiskiImage = 'hiwiski-image';
}

/// Who the app comes from and under which terms (LICENSE.md).
abstract final class ProjectInfo {
  /// Holds the copyright — the `Required Notice` in LICENSE.md.
  static const author = 'Daniel Kononov';

  /// The license's name as PolyForm writes it; not translated.
  static const license = 'PolyForm Noncommercial 1.0.0';
  static final licenseUrl = Uri.https(
    'polyformproject.org',
    '/licenses/noncommercial/1.0.0',
  );
  static final sourceUrl = Uri.https('github.com', '/danielkono/hiwiski');

  /// Whether [sourceUrl] leads anywhere. The repository is public; a copy that is
  /// kept private turns the link off here.
  static const sourcePublic = true;

  /// What the app itself does with data — the policy the app stores ask for, one page
  /// per language. Not an instance's: that one is its
  /// operator's. Kept at this address for as long as an app that knows
  /// it is in use, even after a move to another domain: builds from before the move
  /// to hiwiski.app link to https://hiwiski.danielkononov.de/app/, which still
  /// serves the same pages.
  static const appPrivacyBase = 'https://hiwiski.app/app/';

  /// The page for a language; [appPrivacyDefault] for every other.
  static const appPrivacyPages = {'de': 'datenschutz'};
  static const appPrivacyDefault = 'privacy';
}
