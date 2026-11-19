import '../common/server_address.dart';
import '../../core/common/app_names.dart';

const _inviteHost = 'invite';
const _hostParam = 'host';
const _codeParam = 'code';

/// `hiwiski://invite?host=…&code=…` — the content of the invitation QR.
typedef InviteLink = ({ServerAddress server, String code});

/// Reads an invitation link; anything else is `null`. The host may come with or without
/// a scheme — `ServerAddress.parse` fills in what is missing.
InviteLink? parseInviteLink(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      uri.scheme != UriSchemes.hiwiski ||
      uri.host != _inviteHost) {
    return null;
  }
  final server = ServerAddress.parse(uri.queryParameters[_hostParam] ?? '');
  final code = uri.queryParameters[_codeParam]?.trim();
  if (server == null || code == null || code.isEmpty) return null;
  return (server: server, code: code);
}

/// Whether following [link] would switch the app away from [currentAddress] — and
/// so has to be confirmed first.
bool leadsElsewhere(InviteLink link, String? currentAddress) =>
    link.server.baseUrl != currentAddress;
