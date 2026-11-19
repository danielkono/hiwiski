import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// An ordinary download, into the browser's downloads.
Future<bool> saveArchive(String name, Uint8List bytes) async {
  final url = web.URL.createObjectURL(web.Blob([bytes.toJS].toJS));
  web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..click();
  // Not at once: the browser reads the file after the click returns.
  Future<void>.delayed(_revokeAfter, () => web.URL.revokeObjectURL(url));
  return true;
}

const _revokeAfter = Duration(minutes: 1);
