import 'dart:typed_data';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/repositories.dart';

part 'member_avatar_view_model.g.dart';

/// A member's picture, from the media store. The preview (longest edge 640) is
/// plenty for a circle of at most 52.
@riverpod
class MemberAvatarViewModel extends _$MemberAvatarViewModel {
  @override
  Stream<Uint8List> build(String imageId) =>
      ref.watch(mediaRepositoryProvider).watchImage(imageId, preview: true);
}
