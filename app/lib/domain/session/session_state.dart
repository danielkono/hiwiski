import 'package:meta/meta.dart';

import '../../core/api/generated/export.dart';
import '../common/server_address.dart';

/// Where the app currently stands.
///
/// The start screen follows from this and is not decided by the screens themselves —
/// otherwise there are two opinions on whether someone is signed in.
enum SessionStage {
  /// No server address yet. Before anything else.
  noServer,

  /// The server does not answer. Everything stays usable as soon as there is something
  /// to use — before the first sign-in there is not.
  unreachable,

  /// The instance is not set up yet: straight into the wizard.
  setupRequired,

  /// Set up, but nobody signed in.
  signedOut,

  /// Signed in, but the administrator has reset the password. The session may do
  /// exactly the password change and nothing else.
  passwordChangeRequired,

  /// Signed in and ready to work.
  signedIn,

  /// Used without a server: the member was made on this device and
  /// exists nowhere else. Everything that needs no server works; nothing syncs.
  /// Connecting to a server later takes the data along.
  localOnly,

  /// This device lost its access by itself — signed out on another device, a session
  /// that ended. Its data stays, locked: whoever signs in again as the same member
  /// keeps it and their changes not yet synced; anyone else signing in clears it.
  /// [SessionState.session] still names whom it belongs to.
  accessLost,
}

@immutable
class SessionState {
  const SessionState({
    required this.stage,
    this.handshake,
    this.session,
    this.serverAddress,
    this.busy = false,
    this.restoreBegun = false,
  });

  final SessionStage stage;
  final Handshake? handshake;
  final Session? session;
  final String? serverAddress;
  final bool busy;

  /// This device heard that a restore began — it started it, or a change of its was
  /// refused for it — before a handshake said so.
  final bool restoreBegun;

  Member? get member => session?.member;

  bool get isAdmin => member?.isAdmin ?? false;

  /// A backup is being restored on the server: until it is done nothing can be
  /// changed, on any device.
  bool get restoring => restoreBegun || (handshake?.restoring ?? false);

  /// Whether a server stands behind the session — sharing, the family, history and
  /// everything else that exists only there. Without one, those entries are hidden,
  /// not shown and refused (no button that only produces an error).
  bool get hasServer => stage != .localOnly;

  /// Whether the app can be used: signed in, or on its own without a server.
  bool get isInside => stage == .signedIn || stage == .localOnly;

  /// Does the connection run in plain text? The app says so instead of showing a lock
  /// that isn't one.
  ///
  /// The address in use counts as well as the handshake: behind a redirect from
  /// `http://` to `https://` the handshake reported TLS while every call -- a new
  /// member's password first -- still went out to the `http://` address.
  bool get isCleartext =>
      (handshake?.cleartext ?? false) ||
      (ServerAddress.parse(serverAddress ?? '')?.isCleartext ?? false);

  SessionState copyWith({
    SessionStage? stage,
    Handshake? handshake,
    Session? session,
    String? serverAddress,
    bool? busy,
    bool? restoreBegun,
    bool clearSession = false,
  }) => .new(
    stage: stage ?? this.stage,
    handshake: handshake ?? this.handshake,
    session: clearSession ? null : (session ?? this.session),
    serverAddress: serverAddress ?? this.serverAddress,
    busy: busy ?? this.busy,
    restoreBegun: restoreBegun ?? this.restoreBegun,
  );
}
