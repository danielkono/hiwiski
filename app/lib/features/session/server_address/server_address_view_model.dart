import 'package:meta/meta.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/stores.dart';
import '../../../core/api/generated/export.dart' hide Mutation;
import '../../../core/common/command.dart';
import '../../../domain/common/server_address.dart';
import '../../../domain/session/session_state.dart';

part 'server_address_view_model.g.dart';

/// `connect`, run by a view: it shows the command running and reacts to how it ended.
final connectMutation = Mutation<Handshake>(
  label: 'serverAddressViewModel.connect',
);

/// The server address, and what else there is to do on its screen.
@immutable
class const ServerAddressState({
  required final SessionState session,

  /// Whether the app can be started without a server here — in the apps, before
  /// anything else; not in the browser, which always comes from a server.
  final bool offerLocal = false,

  /// The device is used without a server and is about to connect to one: its data
  /// goes along, and there is a way back.
  final bool fromLocal = false,
});

/// The server address: the one known, and connecting to another.
@riverpod
class ServerAddressViewModel extends _$ServerAddressViewModel {
  @override
  ServerAddressState build() {
    final session = ref.watch(sessionProvider);
    final store = ref.read(sessionStoreProvider);
    return ServerAddressState(
      session: session,
      offerLocal:
          session.stage == .noServer && !ref.watch(servedWebAppProvider),
      fromLocal: session.stage == .localOnly || store.connectingFromLocal,
    );
  }

  /// Starts the app without a server, under [displayName].
  Future<void> startLocal(String displayName) =>
      ref.read(sessionStoreProvider).startLocal(displayName);

  /// Back to using the app without a server, as it was.
  Future<void> backToLocal() => ref.read(sessionStoreProvider).backToLocal();

  /// Returns the handshake: whether the server is set up yet decides where the
  /// screen goes on to — the wizard or sign-in.
  @command
  Future<Handshake> connect(ServerAddress address) =>
      ref.read(sessionStoreProvider).connect(address);
}
