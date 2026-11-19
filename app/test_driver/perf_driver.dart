import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Writes what `integration_test/perf_test.dart` reports to `build/perf/<PERF_OUT>.json`.
Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final name = Platform.environment['PERF_OUT'] ?? 'perf';
    final file = File('build/perf/$name.json');
    await file.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  },
);
