import 'package:flutter/widgets.dart';

/// The keys the tests find this area's widgets by.
abstract final class HistoryKeys {
  static const _version = 'history-version-';

  /// "Back" from a version to the list.
  static const versionBack = ValueKey('history-version-back');

  /// The row that opens the version [revisionId].
  static ValueKey<String> version(String revisionId) =>
      .new('$_version$revisionId');
}
