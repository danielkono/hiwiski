import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The longest edge any image of the media store is decoded to, in pixels — room to
/// zoom into a photo on a large screen, and at most 64 MB of pixels.
///
/// An image's bytes say nothing about the memory its pixels take: a WebP of a few
/// kilobytes may declare 16384×16384, a gigabyte decoded. The server refuses more
/// than 100 megapixels, but what arrived before that check, or from a device without a
/// server, still has to be safe to show.
const maxDecodeEdge = 4096;

/// The most pixels an image is decoded with when the decoder cannot make it smaller
/// on the way: a PNG or a GIF, and any animated image. Flutter decodes those whole
/// and only then resizes, and ignores the target size of an animation altogether —
/// a 10000×10000 canvas cost 400 MB per frame.
/// [maxDecodeEdge] squared: 64 MB.
const maxWholeDecodePixels = maxDecodeEdge * maxDecodeEdge;

/// The most pixels per frame for an animated image: two frames are held at once.
const maxAnimatedPixels = 2048 * 2048;

/// An image that would take more memory than [maxWholeDecodePixels] or
/// [maxAnimatedPixels] allow to decode here. Shown as the server's preview where
/// there is one, otherwise as an image that failed.
class ImageTooLargeError extends Error {
  ImageTooLargeError(this.width, this.height, {required this.animated});

  final int width;
  final int height;
  final bool animated;

  @override
  String toString() =>
      'ImageTooLargeError: ${animated ? 'animated ' : ''}${width}x$height';
}

/// [bytes] decoded no larger than [width] × [height] pixels, keeping their shape —
/// and never larger than [maxDecodeEdge] on either side. A smaller image stays as it
/// is. One the decoder would take whole beyond its limits fails with
/// [ImageTooLargeError] before a pixel is decoded.
ImageProvider boundedImage(Uint8List bytes, {int? width, int? height}) =>
    ResizeImage(
      _CheckedMemoryImage(bytes),
      width: math.min(width ?? maxDecodeEdge, maxDecodeEdge),
      height: math.min(height ?? maxDecodeEdge, maxDecodeEdge),
      policy: .fit,
    );

const _debugLabel = 'BoundedImage';

/// The bytes looked at — size from the header, number of frames — before they are
/// handed to the decoder.
///
/// Without fields of its own: MemoryImage's `==`, which compares the runtime type,
/// the bytes and the scale, is already the right one for the image cache.
// ignore: many_lints/prefer_overriding_parent_equality
class _CheckedMemoryImage extends MemoryImage {
  const _CheckedMemoryImage(super.bytes);

  @override
  ImageStreamCompleter loadImage(
    MemoryImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _checked(decode),
    scale: key.scale,
    debugLabel: kDebugMode ? '$_debugLabel(${describeIdentity(key)})' : null,
  );

  Future<ui.Codec> _checked(ImageDecoderCallback decode) async {
    await checkDecodable(bytes);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }
}

/// Throws [ImageTooLargeError] when [bytes] would be decoded whole past the limits.
///
/// Reads only the header and the number of frames: neither decodes a pixel. Not on
/// the web, whose engine reads no header of its own: there the browser decodes.
@visibleForTesting
Future<void> checkDecodable(Uint8List bytes) async {
  if (kIsWeb) return;
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final ui.ImageDescriptor descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
  } finally {
    buffer.dispose();
  }
  try {
    final pixels = descriptor.width * descriptor.height;
    if (pixels <= maxAnimatedPixels) return;
    final codec = await descriptor.instantiateCodec();
    final animated = codec.frameCount > 1;
    codec.dispose();
    final limit = animated ? maxAnimatedPixels : _wholeDecodeLimit(bytes);
    if (limit != null && pixels > limit) {
      throw ImageTooLargeError(
        descriptor.width,
        descriptor.height,
        animated: animated,
      );
    }
  } finally {
    descriptor.dispose();
  }
}

/// The most pixels a still image may have: no limit for a format the decoder makes
/// smaller on the way, [maxWholeDecodePixels] for one it decodes whole.
int? _wholeDecodeLimit(Uint8List bytes) =>
    _scalesWhileDecoding(bytes) ? null : maxWholeDecodePixels;

/// JPEG and (still) WebP: the decoder makes them smaller on the way, so only the
/// target size counts.
bool _scalesWhileDecoding(Uint8List b) =>
    (b.length >= 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) ||
    (b.length >= 12 &&
        b[0] == _r &&
        b[1] == _i &&
        b[2] == _f &&
        b[3] == _f &&
        b[8] == _w &&
        b[9] == _e &&
        b[10] == _b &&
        b[11] == _p);

// The letters of "RIFF" and "WEBP", as bytes.
const _r = 0x52;
const _i = 0x49;
const _f = 0x46;
const _w = 0x57;
const _e = 0x45;
const _b = 0x42;
const _p = 0x50;
