import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/stores.dart';
import '../../core/api/generated/export.dart';

part 'account_avatar_view_model.g.dart';

/// Who is signed in — the avatar in the page header that leads to the account.
@riverpod
class AccountAvatarViewModel extends _$AccountAvatarViewModel {
  @override
  Member? build() => ref.watch(sessionProvider.select((s) => s.member));
}
