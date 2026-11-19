import 'package:flutter/widgets.dart' show FocusManager;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/common/build_flavor.dart';
import 'stores.dart';
import '../domain/session/session_state.dart';
import '../core/routing/not_found_screen.dart';
import '../core/routing/routes.dart';

part 'router.g.dart';

/// The router that derives the start screen from the session state.
///
/// The switch lives in exactly one place. If it lived in the screens there would be two
/// opinions on whether someone is signed in — and one of them would be stale at some
/// point.
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final refresh = _SessionRefresh(ref);
  ref.onDispose(refresh.dispose);

  // **A direct link survives a reload.** Without a remembered session the session is
  // not there yet at startup (the handshake is running), so the switch first sends to
  // sign-in and after the handshake to start. That is why it remembers the address it
  // was sent away from and returns there as soon as the session is in place.
  //
  // On every such demotion, not only the first decision: a remembered session starts
  // signed in, and when the handshake then refused it — or asked for a new password —
  // the link was gone. Whoever signs out deliberately is on start by then (the account
  // screen goes there first), so they start on start.
  String? pending;

  final router = GoRouter(
    initialLocation: const HomeRoute().location,
    routes: $appRoutes,
    // An address without a screen: said in the app's words, not Flutter's error page.
    errorBuilder: (context, state) => const NotFoundScreen(),
    refreshListenable: refresh,
    redirect: (context, state) {
      String takePending() {
        final target = pending ?? const HomeRoute().location;
        pending = null;
        return target;
      }

      final session = ref.read(sessionProvider);
      final path = state.uri.path;
      if (!session.isInside &&
          pending == null &&
          !_isBeforeSignIn(path) &&
          !_isKiosk(path) &&
          path != const HomeRoute().location) {
        pending = state.uri.toString();
      }

      // **The wall tablet board has nothing to do with the session.** It runs under
      // its own address, without sign-in, and so must not be redirected anywhere —
      // not even to the sign-in screen when the server is unreachable at the moment.
      if (_isKiosk(path)) return null;

      // Administrators only. The account hid the row, but a link or a restored web
      // address opened the whole settings form for anyone — with every request
      // refused: a button that only produces an error.
      if (path == const SettingsRoute().location &&
          session.stage == .signedIn &&
          !session.isAdmin) {
        return const AccountRoute().location;
      }

      // Without a server, what exists only on one leads back to the account — a
      // link or a restored web address would open a screen whose every request fails.
      if (!session.hasServer && _needsServer(path)) {
        return const AccountRoute().location;
      }

      return switch (session.stage) {
        .noServer =>
          path == const ServerAddressRoute().location
              ? null
              : const ServerAddressRoute().location,
        .setupRequired =>
          path == const SetupRoute().location
              ? null
              : const SetupRoute().location,
        // As long as the password has not been changed, every path leads here and
        // nowhere else.
        .passwordChangeRequired =>
          path == const PasswordChangeRoute().location
              ? null
              : const PasswordChangeRoute().location,
        .signedOut =>
          _allowedSignedOut(path) ? null : const LoginRoute().location,
        // Unreachable does not mean locked out: the address is set, the app shows the
        // sign-in screen with a notice. Whoever was already signed in keeps working —
        // that is only decided once the handshake gets through.
        .unreachable =>
          _allowedSignedOut(path) ? null : const LoginRoute().location,
        // Locked, not signed out: the lock screen, and from there the sign-in —
        // nothing else shows the data.
        .accessLost =>
          _allowedLocked(path) ? null : const AccessLostRoute().location,
        .signedIn => _isBeforeSignIn(path) ? takePending() : null,
        // The server address stays reachable: from there the device connects to a
        // server and takes its data along. Not in the demo, which has none to offer.
        .localOnly =>
          _isBeforeSignIn(path) &&
                  (BuildFlavor.demo ||
                      path != const ServerAddressRoute().location)
              ? takePending()
              : null,
      };
    },
  );

  // **Another screen, no keyboard.** On the iPhone the keyboard stayed open after
  // leaving a screen whose field had it — a page being edited, a task — and nothing
  // left on the new screen could close it. Whatever had the focus gives it up as
  // soon as the address changes.
  String? shown;
  void dropFocus() {
    final address = router.routerDelegate.currentConfiguration.uri.toString();
    if (address == shown) return;
    shown = address;
    FocusManager.instance.primaryFocus?.unfocus();
  }

  router.routerDelegate.addListener(dropFocus);
  ref.onDispose(() => router.routerDelegate.removeListener(dropFocus));
  return router;
}

/// The board on the wall tablet: its own address, no session, no way into the app.
bool _isKiosk(String path) =>
    path.startsWith(const KioskRoute(token: '').location);

/// What exists only on a server: the family and its devices, the instance's
/// settings, the dashboard's address for the wall tablet, the password.
bool _needsServer(String path) => {
  const FamilyRoute().location,
  const DevicesRoute().location,
  const SettingsRoute().location,
  const DashboardRoute().location,
  const PasswordChangeRoute().location,
}.contains(path);

/// Reachable before sign-in: server address, sign in, redeem invitation.
bool _allowedSignedOut(String path) =>
    path == const LoginRoute().location ||
    path == const ServerAddressRoute().location ||
    path == const RedeemInvitationRoute().location;

/// Reachable while the device is locked: the lock screen, signing in again, and the
/// server address.
bool _allowedLocked(String path) =>
    path == const AccessLostRoute().location ||
    path == const LoginRoute().location ||
    path == const ServerAddressRoute().location;

/// Everything that only exists before sign-in.
///
/// Whoever is signed in has no business here any more — and that includes the setup
/// wizard. Without this line it stayed put after the last step even though the
/// session had long been in place, and a second tap ran into
/// `setup.already_completed`.
bool _isBeforeSignIn(String path) =>
    _allowedSignedOut(path) ||
    path == const AccessLostRoute().location ||
    path == const SetupRoute().location ||
    path == const PasswordChangeRoute().location;

/// Lets the router decide again as soon as the session state changes.
class _SessionRefresh extends ChangeNotifier {
  _SessionRefresh(Ref ref) {
    _subscription = ref.listen<SessionState>(sessionProvider, (previous, next) {
      if (previous?.stage != next.stage) notifyListeners();
    });
  }

  late final ProviderSubscription<SessionState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
