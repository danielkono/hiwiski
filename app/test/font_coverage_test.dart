import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// **Every character of the texts is in the app's own font.** The web version loads
/// no font from elsewhere: a character Roboto lacks — "✕" on a tag,
/// "→" in a hint — showed as an empty box. A symbol comes from
/// `HiwiskiSymbols`, not from the text.
void main() {
  final roboto = _codepoints(File('fonts/Roboto.ttf').readAsBytesSync());

  List<String> missing(String text) => [
    for (final rune in text.runes)
      if (rune > 127 && !roboto.contains(rune)) String.fromCharCode(rune),
  ];

  test('the font is read right', () {
    expect(missing('Größe „Milch“ – 2 l · …'), isEmpty);
    expect(missing('Milch ✕ →'), equals(['✕', '→']));
  });

  test('the UI texts', () {
    for (final file in Directory('lib/core/l10n').listSync()) {
      if (file is! File || !file.path.endsWith('.arb')) continue;
      final texts = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in texts.entries) {
        if (key.startsWith('@') || value is! String) continue;
        expect(missing(value), isEmpty, reason: '${file.path}: $key');
      }
    }
  });

  test('the strings in the code', () {
    for (final file in Directory('lib').listSync(recursive: true)) {
      final path = file.path;
      if (file is! File ||
          !path.endsWith('.dart') ||
          path.contains('/generated/') ||
          path.endsWith('.g.dart')) {
        continue;
      }
      for (final (index, line) in file.readAsLinesSync().indexed) {
        // Comments may say anything.
        final code = line.split('//').first;
        expect(missing(code), isEmpty, reason: '$path:${index + 1}');
      }
    }
  });
}

/// The characters a TrueType font has, from its `cmap` (formats 4 and 12).
Set<int> _codepoints(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  int u16(int at) => data.getUint16(at);
  int u32(int at) => data.getUint32(at);

  int? cmap;
  for (int i = 0; i < u16(4); i++) {
    final entry = 12 + 16 * i;
    if (ascii.decode(bytes.sublist(entry, entry + 4)) == 'cmap') {
      cmap = u32(entry + 8);
    }
  }
  if (cmap == null) throw StateError('no cmap table');

  final codepoints = <int>{};
  for (int i = 0; i < u16(cmap + 2); i++) {
    final table = cmap + u32(cmap + 4 + 8 * i + 4);
    switch (u16(table)) {
      case 4:
        final segments = u16(table + 6) ~/ 2;
        for (int s = 0; s < segments; s++) {
          final end = u16(table + 14 + 2 * s);
          final start = u16(table + 16 + 2 * segments + 2 * s);
          for (int c = start; c <= end; c++) {
            codepoints.add(c);
          }
        }
      case 12:
        for (int g = 0; g < u32(table + 12); g++) {
          final group = table + 16 + 12 * g;
          for (int c = u32(group); c <= u32(group + 4); c++) {
            codepoints.add(c);
          }
        }
    }
  }
  return codepoints;
}
