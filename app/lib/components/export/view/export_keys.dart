import 'package:flutter/foundation.dart';

/// The export's widgets a test looks for.
abstract final class ExportKeys {
  static const open = ValueKey('export-open');
  static const withDone = ValueKey('export-with-done');
  static const withSubpages = ValueKey('export-with-subpages');
  static const withImages = ValueKey('export-with-images');
  static const withPinboards = ValueKey('export-with-pinboards');
  static const run = ValueKey('export-run');
}
