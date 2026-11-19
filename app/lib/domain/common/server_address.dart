import '../../core/common/app_names.dart';

/// The address of the home server.
///
/// It is typed in by hand, on the home network, often without scheme and without port.
/// This class turns it into a usable base URL and says whether the connection runs in
/// plain text — the app says so in plain words instead of showing a lock that isn't
/// one.
class ServerAddress {
  const ServerAddress._(this.uri);

  final Uri uri;

  bool get isCleartext => uri.scheme == UriSchemes.http;

  String get display =>
      uri.host + (uri.hasPort ? ':${uri.port}' : '') + uri.path;

  String get baseUrl => uri.toString().replaceAll(RegExp(r'/+$'), '');

  /// Fills in what people tend to leave out when typing.
  ///
  /// Without a scheme `http` is assumed, not `https`: on the home network plain text
  /// is the path most people take, and silently reaching for
  /// `https` would run into a certificate warning nobody can make sense of.
  static ServerAddress? parse(String input) {
    String text = input.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) {
      text = '${UriSchemes.http}://$text';
    }
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != UriSchemes.http && uri.scheme != UriSchemes.https) {
      return null;
    }
    // The path stays: behind a reverse proxy the server may live at
    // `https://nas.local/hiwiski`, and dropped, every call went to the proxy's root
    // and came back 404 with no hint why. A trailing slash says nothing.
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    return ServerAddress._(
      Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: path.isEmpty ? null : path,
      ),
    );
  }

  @override
  String toString() => baseUrl;

  @override
  bool operator ==(Object other) => other is ServerAddress && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}
