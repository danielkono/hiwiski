import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/hiwiski_metrics.dart';
import 'cleartext_warning.dart';
import '../../domain/common/server_address.dart';
import 'ui_keys.dart';

/// Asks before an invitation link switches the app to its server.
///
/// The link names the server itself, and a signed-out device used to connect to it at
/// once and show only the family name the server reports — any server can call itself
/// "Müller". Whoever then picked a name and a password gave them to whoever sent the
/// link. So the address is shown first, with the
/// same warning the manual server step has for a connection without encryption.
///
/// `true` to connect; `false` when the person declines or dismisses the dialog.
Future<bool> confirmInviteServer(
  BuildContext context,
  ServerAddress server,
) async {
  final l = L.of(context);
  final agreed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: CoreKeys.inviteServerDialog,
      title: Text(l.inviteServerTitle),
      content: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        spacing: HiwiskiMetrics.space16,
        children: [
          Text(l.inviteServerBody(server.display)),
          if (server.isCleartext) const CleartextWarning(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          key: CoreKeys.inviteServerConnect,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.inviteServerConnect),
        ),
      ],
    ),
  );
  return agreed ?? false;
}
