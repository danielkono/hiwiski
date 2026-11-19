import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// The system's save dialog — on a phone it is also the way into the Files app or a
/// cloud drive. Returns whether it was saved.
Future<bool> saveArchive(String name, Uint8List bytes) async =>
    await FilePicker.saveFile(fileName: name, bytes: bytes) != null;
