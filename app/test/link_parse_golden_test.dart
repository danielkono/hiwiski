import 'dart:convert';
import 'dart:io';

import 'package:hiwiski/domain/links/link_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parsing references against `golden/links.json`.
///
/// **The server checks the same file.** It parses the text to write the `link` table; the
/// device parses it to draw the chips and to fill the info bar offline. Whoever adds a
/// case adds it to the golden file; whoever gets it green on only one side has found the
/// difference that needs to be resolved.
void main() {
  final golden = jsonDecode(
    File('../golden/links.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cases = (golden['cases'] as List).cast<Map<String, dynamic>>();

  test('the golden file contains cases', () => expect(cases, isNotEmpty));

  for (final testCase in cases) {
    test(testCase['name'] as String, () {
      expect(
        [
          for (final reference in parseReferences(testCase['text'] as String))
            reference.normalized,
        ],
        testCase['expected'],
        reason: testCase['why'] as String?,
      );
    });
  }

  group('splitting for display', () {
    test('the bracket of the selection disappears with the reference', () {
      final parts = splitReferences(
        'Siehe [Router](hiwiski://wiki_page/'
        '01932b3c-4d5e-7f80-8a1b-2c3d4e5f6071) und sonst nichts.',
      );

      expect(parts, hasLength(3));
      expect((parts[0] as PlainPart).text, equals('Siehe '));
      // Not "Siehe [Router](…)" — otherwise the brackets would stand next to the chip.
      expect((parts[1] as ReferencePart).reference, isA<UriReference>());
      expect((parts[2] as PlainPart).text, equals(' und sonst nichts.'));
    });

    test('the same reference twice is drawn twice', () {
      final parts = splitReferences('#TD-14 und wieder #TD-14');

      expect(parts.whereType<ReferencePart>(), hasLength(2));
      // The table knows it once, the sentence twice.
      expect(parseReferences('#TD-14 und wieder #TD-14'), hasLength(1));
    });
  });
}
