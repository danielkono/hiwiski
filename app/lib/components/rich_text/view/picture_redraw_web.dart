import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// [bytes] drawn again as a JPEG by the browser, its longer side at most [edge] —
/// with its file ending; `null` when the browser cannot read them.
///
/// The browser, not the app's engine: drawn by the engine into a picture of its
/// own, a photo Safari had decoded came out black. The browser reads what it shows,
/// turns a photo as its camera did, and leaves its location and camera data out.
Future<({Uint8List bytes, String ending})?> redrawPicture(
  Uint8List bytes, {
  required double edge,
}) async {
  final url = web.URL.createObjectURL(web.Blob([bytes.toJS].toJS));
  try {
    final image = web.HTMLImageElement()..src = url;
    await image.decode().toDart;
    final across = image.naturalWidth;
    final down = image.naturalHeight;
    if (across <= 0 || down <= 0) return null;
    final scale = math.min(1.0, edge / math.max(across, down));
    final width = math.max(1, (across * scale).round());
    final height = math.max(1, (down * scale).round());
    final canvas = web.HTMLCanvasElement()
      ..width = width
      ..height = height;
    // A JPEG has no transparency: on white, as the server's previews are.
    canvas.context2D
      ..fillStyle = _white.toJS
      ..fillRect(0, 0, width, height)
      ..drawImage(image, 0, 0, width, height);
    final done = Completer<web.Blob?>();
    canvas.toBlob(
      ((web.Blob? blob) => done.complete(blob)).toJS,
      _jpeg,
      _quality.toJS,
    );
    final blob = await done.future;
    if (blob == null) return null;
    return (
      bytes: (await blob.arrayBuffer().toDart).toDart.asUint8List(),
      ending: _jpg,
    );
  } on Object catch (error) {
    debugPrint('hiwiski: picture not redrawn: $error');
    return null;
  } finally {
    web.URL.revokeObjectURL(url);
  }
}

const _white = '#ffffff';
const _jpeg = 'image/jpeg';
const _jpg = '.jpg';

/// Close to the camera's own; a photo stays sharp and well below the upload limit.
const _quality = 0.9;
