import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// [bytes] drawn again as a PNG, its longer side at most [edge] — with its file
/// ending; `null` when the device cannot read them.
Future<({Uint8List bytes, String ending})?> redrawPicture(
  Uint8List bytes, {
  required double edge,
}) async {
  final ui.Codec codec;
  try {
    codec = await ui.instantiateImageCodec(bytes);
  } on Object catch (error) {
    debugPrint('hiwiski: picture not redrawn: $error');
    return null;
  }
  ui.Image? image;
  try {
    image = (await codec.getNextFrame()).image;
    final scale = math.min(1.0, edge / math.max(image.width, image.height));
    final width = math.max(1, (image.width * scale).round());
    final height = math.max(1, (image.height * scale).round());
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..scale(width / image.width, height / image.height)
      ..drawImage(image, ui.Offset.zero, ui.Paint());
    final picture = recorder.endRecording();
    // The picture is drawn only now: the image it shows stays until then.
    final drawn = await picture.toImage(width, height);
    picture.dispose();
    final png = await drawn.toByteData(format: ui.ImageByteFormat.png);
    drawn.dispose();
    if (png == null) return null;
    return (bytes: png.buffer.asUint8List(), ending: _png);
  } finally {
    image?.dispose();
    codec.dispose();
  }
}

const _png = '.png';
