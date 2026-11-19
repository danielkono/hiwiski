import 'package:flutter/widgets.dart';

/// The keys the tests find this area's widgets by.
abstract final class FamilyKeys {
  static const _revoke = 'family-revoke-';

  /// "Withdraw" on the row of the open invitation [id].
  static ValueKey<String> revoke(String id) => .new('$_revoke$id');

  /// The confirmation's "Withdraw".
  static const revokeConfirm = ValueKey('family-revoke-confirm');
}
