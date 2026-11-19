import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/ui/bounded_image.dart';

/// **An image is never decoded at the size its file declares**: a small file may declare a gigabyte of pixels.
void main() {
  Future<Uint8List> png(int width, int height) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFF336699),
    );
    final image = await recorder.endRecording().toImage(width, height);
    final data = await image.toByteData(format: .png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  Future<(int, int)> decoded(ImageProvider provider) {
    final done = Completer<(int, int)>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      done.complete((info.image.width, info.image.height));
      info.dispose();
      stream.removeListener(listener);
    }, onError: (error, stack) => done.completeError(error, stack));
    stream.addListener(listener);
    return done.future;
  }

  testWidgets('the whole image stops at the longest edge it may have', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = await png(2 * maxDecodeEdge, maxDecodeEdge ~/ 4);

      expect(
        await decoded(boundedImage(bytes)),
        equals((maxDecodeEdge, maxDecodeEdge ~/ 8)),
      );
    });
  });

  /// A GIF by hand: a logical screen of [width] × [height] and [frames] frames of
  /// 1×1 — the descriptor claims the screen, the data is a pixel each.
  Uint8List gif(int width, int height, {int frames = 1}) {
    final bytes = <int>[
      ...'GIF89a'.codeUnits,
      width & 0xff, width >> 8, height & 0xff, height >> 8, 0, 0, 0,
      // Loop forever, so that two frames are an animation.
      0x21, 0xff, 11, ...'NETSCAPE2.0'.codeUnits, 3, 1, 0, 0, 0,
    ];
    for (int i = 0; i < frames; i++) {
      bytes.addAll([
        0x21, 0xf9, 4, 0, 10, 0, 0, 0, // a tenth of a second per frame
        0x2c, 0, 0, 0, 0, 1, 0, 1, 0, 0x80, 0, 0, 0, 0xff, 0xff, 0xff,
        2, 2, 0x44, 0x01, 0,
      ]);
    }
    bytes.add(0x3b);
    return Uint8List.fromList(bytes);
  }

  // PNG and GIF are decoded whole, an animation
  // at its full canvas whatever size is asked for.
  testWidgets('what would be decoded whole past the limits is refused', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // The review's GIF: a 30000×30000 screen around one 1×1 frame, 3.6 GB.
      await expectLater(
        checkDecodable(gif(30000, 30000)),
        throwsA(isA<ImageTooLargeError>()),
      );
      await expectLater(
        checkDecodable(gif(3000, 3000, frames: 2)),
        throwsA(
          isA<ImageTooLargeError>().having((e) => e.animated, 'animated', true),
        ),
      );
      await expectLater(
        checkDecodable(await png(5000, 4000)),
        throwsA(isA<ImageTooLargeError>()),
      );
      // Through the provider, as the views load it.
      await expectLater(
        decoded(boundedImage(gif(30000, 30000), width: 100)),
        throwsA(isA<ImageTooLargeError>()),
      );
      // Small enough: decoded as before.
      await checkDecodable(gif(1000, 1000, frames: 2));
      await checkDecodable(await png(4000, 4000));
    });
  });

  testWidgets('a width asked for keeps the shape and bounds the height too', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = await png(400, 200);

      expect(await decoded(boundedImage(bytes, width: 100)), equals((100, 50)));
      // A small image stays as it is.
      expect(
        await decoded(boundedImage(bytes, width: 800)),
        equals((400, 200)),
      );
    });
  });
}
