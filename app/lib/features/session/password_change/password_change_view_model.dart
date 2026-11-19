import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/stores.dart';

part 'password_change_view_model.g.dart';

/// The password change the administrator's reset demands.
@riverpod
class PasswordChangeViewModel extends _$PasswordChangeViewModel {
  @override
  void build() {}

  Future<void> change(String current, String next) =>
      ref.read(sessionStoreProvider).changePassword(current, next);
}
