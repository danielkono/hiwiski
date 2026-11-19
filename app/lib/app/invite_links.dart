import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import '../core/routing/routes.dart';
import '../domain/invite/invite_link.dart';
import '../core/ui/invite_server_dialog.dart';
import 'stores.dart';

/// Follows an invitation link: **first to the right server**, then to "Redeem
/// invitation" with the code. Anyone already signed in belongs to a family — there a
/// foreign link changes nothing.
///
/// **A server other than the current one is only connected to once the person has
/// seen its address and said yes**: the link names
/// the server, and anyone can send one that leads to theirs.
Future<void> followInviteLink(WidgetRef ref, InviteLink link) async {
  final session = ref.read(sessionProvider);
  if (session.member != null) return;
  final router = ref.read(routerProvider);
  if (leadsElsewhere(link, session.serverAddress)) {
    final context = router.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    if (!await confirmInviteServer(context, link.server)) return;
    // Signed in while the question stood: the link changes nothing any more.
    if (ref.read(sessionProvider).member != null) return;
    await ref.read(sessionStoreProvider).connect(link.server);
  }
  router.go(RedeemInvitationRoute(code: link.code).location);
}

/// Listens for links the operating system opens the app with — at startup and while it
/// is running. The browser has no `hiwiski://`; there this does not apply.
StreamSubscription<Uri>? listenForInviteLinks(WidgetRef ref) {
  if (kIsWeb) return null;
  return AppLinks().uriLinkStream.listen((uri) {
    final link = parseInviteLink(uri.toString());
    if (link != null) {
      // Following the link shows its own error on the redeem screen.
      followInviteLink(ref, link).ignore();
    }
  });
}
