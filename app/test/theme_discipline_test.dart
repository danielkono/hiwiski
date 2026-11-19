import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// "No screen writes a color, a font size or a radius directly. A `Color(0xFF3B6939)`
/// outside `core/theme/` is an error and is forbidden by lint."
///
/// Dart has no built-in rule for that, and a custom `custom_lint` rule would be a package
/// for one line. Instead, this test reads the source tree -- it runs in the same pipeline
/// and breaks at the same point.
void main() {
  final lib = Directory('lib');

  /// Color literals in every spelling that might appear in a draft.
  final hardcodedColor = RegExp(
    r'Color\(\s*0x|Colors\.(?!transparent\b)[a-z]',
    caseSensitive: true,
  );

  /// Sizes belong in the `TextTheme` or in `HiwiskiTextStyles`.
  ///
  /// The search is for a **number**, not for every `fontSize:`. A size that follows from
  /// a measurement -- the initial in the avatar grows with its radius, the "f" in the logo
  /// with its edge length -- is not a written-down size but a derived one. The rule is
  /// aimed at `fontSize: 17`.
  final hardcodedFontSize = RegExp(r'fontSize\s*:\s*[0-9]');

  Iterable<File> sourcesOutsideTheme() sync* {
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      // The tokens themselves may write colors -- they are the one place for it.
      if (path.startsWith('lib/core/theme/')) continue;
      yield entity;
    }
  }

  List<String> findings(RegExp pattern) {
    final result = <String>[];
    for (final file in sourcesOutsideTheme()) {
      final lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (pattern.hasMatch(line)) {
          result.add('${file.path}:${i + 1}: ${line.trim()}');
        }
      }
    }
    return result;
  }

  test('no color outside core/theme', () {
    expect(
      findings(hardcodedColor),
      isEmpty,
      reason:
          'Colors come from ColorScheme or HiwiskiTokens, not from the screen.',
    );
  });

  test('no font size outside core/theme', () {
    expect(
      findings(hardcodedFontSize),
      isEmpty,
      reason: 'Font sizes come from the TextTheme or from HiwiskiTextStyles.',
    );
  });
}
