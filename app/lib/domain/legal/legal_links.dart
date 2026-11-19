import 'package:meta/meta.dart';

import '../../core/common/app_names.dart';
import '../../core/common/build_flavor.dart';

/// Where the operator of an instance open to the public keeps its legal notice
/// (Impressum) and privacy policy. A family's own server names neither:
/// a private instance needs none, and the app then shows no "Legal" section.
@immutable
class LegalLinks {
  const LegalLinks({this.notice, this.privacy});

  /// From the addresses as a server or a build names them: empty or unreadable is
  /// none, and a relative one is read against [base] — the page itself, in the
  /// browser.
  factory LegalLinks.from({
    required String? notice,
    required String? privacy,
    required Uri base,
  }) => .new(notice: _resolve(notice, base), privacy: _resolve(privacy, base));

  /// For this build, against the server's addresses in its handshake: the demo, which
  /// has no server, names them when it is built; every other build takes the
  /// server's — or none.
  factory LegalLinks.forInstance({
    required String? notice,
    required String? privacy,
  }) =>
      BuildFlavor.legalNoticeUrl.isNotEmpty || BuildFlavor.privacyUrl.isNotEmpty
      ? .from(
          notice: BuildFlavor.legalNoticeUrl,
          privacy: BuildFlavor.privacyUrl,
          base: .base,
        )
      : .from(notice: notice, privacy: privacy, base: .base);

  /// The app's own privacy policy in [language] (PRIVACY.md) — the same for every
  /// instance. The build may keep it elsewhere ([BuildFlavor.appPrivacyBase]); a
  /// relative place is read against [base], the page itself in the browser.
  static Uri appPrivacy(
    String language, {
    String place = BuildFlavor.appPrivacyBase,
    Uri? base,
  }) {
    final folder = place.trim().isEmpty ? ProjectInfo.appPrivacyBase : place;
    final page =
        ProjectInfo.appPrivacyPages[language] ?? ProjectInfo.appPrivacyDefault;
    return (base ?? .base).resolve(folder).resolve(page);
  }

  final Uri? notice;
  final Uri? privacy;

  bool get isEmpty => notice == null && privacy == null;

  /// Only a web page: the addresses come from the server's handshake, and the
  /// "Legal notice" button launched whatever they named — `sms:`, `tel:`, another
  /// app's scheme. A relative address read against a
  /// base that is no web page (a file, on a phone) is none either.
  static Uri? _resolve(String? address, Uri base) {
    if (address == null || address.trim().isEmpty) return null;
    final uri = Uri.tryParse(address.trim());
    if (uri == null) return null;
    final resolved = uri.hasScheme ? uri : base.resolveUri(uri);
    final web =
        (resolved.scheme == UriSchemes.http ||
            resolved.scheme == UriSchemes.https) &&
        resolved.host.isNotEmpty;
    return web ? resolved : null;
  }

  @override
  bool operator ==(Object other) =>
      other is LegalLinks && other.notice == notice && other.privacy == privacy;

  @override
  int get hashCode => Object.hash(notice, privacy);
}
