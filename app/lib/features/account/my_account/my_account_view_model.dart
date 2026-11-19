import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../app/stores.dart';
import '../../../core/api/generated/export.dart';

part 'my_account_view_model.g.dart';

/// Who one is, and whether there is a password to it.
@immutable
class const MyAccountState({
  required final Member? member,

  /// Made without a server: no username and no password — the member
  /// exists only on this device.
  final bool local = false,
});

/// "My account": one's picture, name and password.
@riverpod
class MyAccountViewModel extends _$MyAccountViewModel {
  @override
  MyAccountState build() {
    final session = ref.watch(sessionProvider);
    return MyAccountState(member: session.member, local: !session.hasServer);
  }

  Future<void> setName(String name) =>
      _changed(ref.read(sessionStoreProvider).updateProfile(displayName: name));

  Future<void> setPicture(Uint8List bytes, String filename) =>
      _changed(ref.read(sessionStoreProvider).uploadAvatar(bytes, filename));

  Future<void> removePicture() => _changed(
    ref.read(sessionStoreProvider).updateProfile(removeAvatar: true),
  );

  Future<void> changePassword(String current, String next) =>
      ref.read(sessionStoreProvider).changePassword(current, next);

  /// The family's list catches up, so chips and comments show the new name and
  /// picture.
  Future<void> _changed(Future<void> change) async {
    final family = ref.read(familyRepositoryProvider);
    await change;
    family.refresh();
  }
}
