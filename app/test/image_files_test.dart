import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/components/rich_text/view/image_files.dart';

/// **A picked picture as the server takes it** — a JPEG, PNG, GIF or WebP within the
/// upload limit as it is, any other the device reads as a PNG.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a PNG within the limit stays as it is', () async {
    final png = await _png(30, 20);
    final served = await servableImage(png, 'strand.png');
    expect(served.bytes, same(png));
    expect(served.filename, equals('strand.png'));
  });

  test(
    'a format the server refuses becomes a PNG of the same picture',
    () async {
      // A BMP stands in for a HEIC: the device reads it, the server does not.
      final served = await servableImage(_bmp(30, 20), 'strand.heic');
      expect(served.bytes.sublist(0, 4), equals([0x89, 0x50, 0x4E, 0x47]));
      expect(served.filename, equals('strand.png'));
      expect(await _sizeOf(served.bytes), equals(const Size(30, 20)));
    },
  );

  test('a picture too large is drawn smaller, in its own shape', () async {
    final served = await servableImage(
      await _png(300, 100),
      'panorama.png',
      limit: 10,
      edge: 120,
    );
    expect(await _sizeOf(served.bytes), equals(const Size(120, 40)));
  });

  test('what the device cannot read stays as it is', () async {
    final garbage = Uint8List.fromList(List.filled(64, 7));
    final served = await servableImage(garbage, 'kaputt.heic');
    expect(served.bytes, same(garbage));
    expect(served.filename, equals('kaputt.heic'));
  });
}

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF2E7D6B),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// A 24-bit BMP of one colour, [width] × [height].
Uint8List _bmp(int width, int height) {
  final row = (width * 3 + 3) & ~3;
  final size = 54 + row * height;
  final data = ByteData(size)
    ..setUint8(0, 0x42)
    ..setUint8(1, 0x4D)
    ..setUint32(2, size, Endian.little)
    ..setUint32(10, 54, Endian.little)
    ..setUint32(14, 40, Endian.little)
    ..setInt32(18, width, Endian.little)
    ..setInt32(22, height, Endian.little)
    ..setUint16(26, 1, Endian.little)
    ..setUint16(28, 24, Endian.little)
    ..setUint32(34, row * height, Endian.little);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final at = 54 + y * row + x * 3;
      data
        ..setUint8(at, 0x6B)
        ..setUint8(at + 1, 0x7D)
        ..setUint8(at + 2, 0x2E);
    }
  }
  return data.buffer.asUint8List();
}

Future<Size> _sizeOf(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  final size = Size(image.width.toDouble(), image.height.toDouble());
  image.dispose();
  codec.dispose();
  return size;
}
