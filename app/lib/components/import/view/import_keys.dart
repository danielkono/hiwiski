import 'package:flutter/foundation.dart';

/// The import's widgets a test looks for.
abstract final class ImportKeys {
  static const open = ValueKey('import-open');
  static const take = ValueKey('import-take');
  static const skipped = ValueKey('import-skipped');
}
