import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/stores.dart';
import '../../../domain/session/session_state.dart';

part 'login_view_model.g.dart';

/// Sign-in: the server one is signing in to, and whether it speaks plain text.
@immutable
class const LoginState({
  required final SessionState session,

  /// The device was used without a server and is on its way to one: whoever signs
  /// in takes its data into their account.
  final bool fromLocal = false,
});

/// Sign-in: the server one is signing in to, and whether it speaks plain text.
@riverpod
class LoginViewModel extends _$LoginViewModel {
  @override
  LoginState build() => .new(
    session: ref.watch(sessionProvider),
    fromLocal: ref.read(sessionStoreProvider).connectingFromLocal,
  );

  /// Back to using the app without a server, as it was.
  Future<void> backToLocal() => ref.read(sessionStoreProvider).backToLocal();

  Future<void> signIn(
    String username,
    String password, {
    required bool staySignedIn,
  }) => ref
      .read(sessionStoreProvider)
      .signIn(username, password, staySignedIn: staySignedIn);
}
