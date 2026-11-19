import 'package:flutter/widgets.dart';

/// The keys the tests find this area's widgets by.
abstract final class ArchiveKeys {
  static const _archive = 'archive-';
  static ValueKey<String> archive(String id) => .new('$_archive$id');
}
