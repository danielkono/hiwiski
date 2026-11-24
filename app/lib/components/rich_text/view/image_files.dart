import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../../core/ui/pick_files.dart';

/// Pictures chosen in the system's dialog, read into memory, each in a form the
/// server takes ([servableImage]) — empty when the choice was cancelled.
///
/// Run inside the upload's mutation, so its spinner covers the whole wait: after the
/// choice the iPhone first converts its photos to JPEG, and a large picture takes a
/// while to read. Until the upload had started nothing showed that anything happened.
///
/// [single]: one picture only.
Future<List<({Uint8List bytes, String filename})>> pickImageFiles({
  bool single = false,
}) async {
  final picked = await pickFiles(type: .image, single: single);
  return [
    for (final file in picked)
      await servableImage(await file.readAsBytes(), file.name),
  ];
}

/// [bytes] as the server takes a picture: a JPEG, PNG, GIF or WebP no larger than an
/// upload may be stays as it is. Any other the device can read — a HEIC from the
/// Files app or a Mac, which the browser shows but the server refuses — or one too
/// large is drawn again as a PNG, its longer side at most [edge].
///
/// A picture kept on the device is uploaded after its page or element has synced;
/// refused then, it was given up without a word, and in the browser, which keeps
/// nothing past the tab, it was gone. One the device cannot read stays as it is:
/// where it is shown, it says so.
///
/// [limit] is the server's (`spring.servlet.multipart.max-file-size` in
/// `server/app/src/main/resources/application.yaml`).
Future<({Uint8List bytes, String filename})> servableImage(
  Uint8List bytes,
  String filename, {
  @visibleForTesting int limit = _uploadLimit,
  @visibleForTesting double edge = _convertedEdge,
}) async {
  if (_servable(bytes) && bytes.length <= limit) {
    return (bytes: bytes, filename: filename);
  }
  final ui.Codec codec;
  try {
    codec = await ui.instantiateImageCodec(bytes);
  } on Object catch (error) {
    debugPrint('hiwiski: picture not converted: $error');
    return (bytes: bytes, filename: filename);
  }
  try {
    final image = (await codec.getNextFrame()).image;
    final scale = math.min(1.0, edge / math.max(image.width, image.height));
    final width = math.max(1, (image.width * scale).round());
    final height = math.max(1, (image.height * scale).round());
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..scale(width / image.width, height / image.height)
      ..drawImage(image, ui.Offset.zero, ui.Paint());
    image.dispose();
    final picture = recorder.endRecording();
    final drawn = await picture.toImage(width, height);
    picture.dispose();
    final png = await drawn.toByteData(format: ui.ImageByteFormat.png);
    drawn.dispose();
    if (png == null) return (bytes: bytes, filename: filename);
    return (bytes: png.buffer.asUint8List(), filename: _asPng(filename));
  } finally {
    codec.dispose();
  }
}

/// Whether [bytes] begin as a JPEG, PNG, GIF or WebP — the formats the server takes.
bool _servable(Uint8List bytes) {
  bool startsWith(List<int> signature, [int at = 0]) =>
      bytes.length >= at + signature.length &&
      [for (final (index, byte) in signature.indexed) bytes[at + index] == byte]
          .every((same) => same);
  return startsWith(_jpeg) ||
      startsWith(_png) ||
      startsWith(_gif) ||
      (startsWith(_riff) && startsWith(_webp, _webpAt));
}

/// [filename] with the ending of a PNG.
String _asPng(String filename) {
  final dot = filename.lastIndexOf(_dot);
  return '${dot > 0 ? filename.substring(0, dot) : filename}$_pngEnding';
}

/// 25 MB, as the server's multipart limit.
const _uploadLimit = 25 * 1024 * 1024;

/// A converted photo's longer side: as a PNG, larger came close to the upload limit.
const _convertedEdge = 2560.0;

const _jpeg = [0xFF, 0xD8, 0xFF];
const _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const _gif = [0x47, 0x49, 0x46, 0x38];
const _riff = [0x52, 0x49, 0x46, 0x46];
const _webp = [0x57, 0x45, 0x42, 0x50];
const _webpAt = 8;
const _dot = '.';
const _pngEnding = '.png';
