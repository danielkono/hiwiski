import 'dart:typed_data';

import '../../../core/ui/pick_files.dart';

/// Pictures chosen in the system's dialog, read into memory — empty when the choice
/// was cancelled.
///
/// Run inside the upload's mutation, so its spinner covers the whole wait: after the
/// choice the iPhone first converts its photos to JPEG, and a large picture takes a
/// while to read. Until the upload had started nothing showed that anything happened.
Future<List<({Uint8List bytes, String filename})>> pickImageFiles() async {
  final picked = await pickFiles(type: .image);
  return [
    for (final file in picked)
      (bytes: await file.xFile.readAsBytes(), filename: file.name),
  ];
}
