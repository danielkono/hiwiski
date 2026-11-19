import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/wiki/markdown_editing.dart';

void main() {
  group('a long page in blocks', () {
    String paragraph(int n) => 'Absatz $n. ${'Text ' * 40}';

    test('a short page stays one block', () {
      expect(markdownChunks('# Titel\n\nkurz'), equals(['# Titel\n\nkurz']));
    });

    test('the blocks joined are the page again', () {
      final page = [for (var i = 0; i < 40; i++) paragraph(i)].join('\n\n');
      final chunks = markdownChunks(page, size: 500);
      expect(chunks.length, greaterThan(1));
      expect(chunks.join('\n'), equals(page));
    });

    test('a code block, a list and an indented line stay whole', () {
      final page = [
        paragraph(1),
        '```\nzeile 1\n\nzeile 2\n```',
        '- eins\n\n- zwei\n\n- drei',
        '1. erstens\n\n    weiter eingerückt',
        paragraph(2),
      ].join('\n\n');
      final chunks = markdownChunks(page, size: 10);
      expect(chunks, contains(contains('zeile 1\n\nzeile 2')));
      expect(chunks, contains(contains('- eins\n\n- zwei\n\n- drei')));
      expect(chunks, contains(contains('erstens\n\n    weiter')));
    });

    test('the boxes of all blocks are those of the page, in order', () {
      final page = [
        for (var i = 0; i < 30; i++) '${paragraph(i)}\n\n- [ ] Aufgabe $i',
      ].join('\n\n');
      final chunks = markdownChunks(page, size: 600);
      expect(
        chunks.map(taskCount).fold(0, (a, b) => a + b),
        equals(taskCount(page)),
      );
      // The first box of the second block is the page's box after the first block's.
      final offset = taskCount(chunks.first);
      final ticked = toggleTask(page, offset);
      expect(
        toggleTask(chunks[1], 0),
        equals(markdownChunks(ticked, size: 600)[1]),
      );
    });
  });

  group('checkboxes on the rendered page', () {
    const packing =
        '# Packing\n- [ ] Passports\n- [x] Charger\n```\n- [ ] not a box\n```\n* [ ] Snacks';

    test('counts what Markdown renders as a checkbox', () {
      expect(taskCount(packing), equals(3));
    });

    test('ticks and unticks the n-th one, code blocks skipped', () {
      expect(toggleTask(packing, 0), contains('- [x] Passports'));
      expect(toggleTask(packing, 1), contains('- [ ] Charger'));
      expect(toggleTask(packing, 2), contains('* [x] Snacks'));
      expect(toggleTask(packing, 2), contains('- [ ] not a box'));
    });
  });

  group('Enter in a list', () {
    ({String text, int cursor})? enter(String before) =>
        continueList('$before\n', before.length + 1);

    test('continues bullets, tasks (unticked) and numbers', () {
      expect(enter('- milk')?.text, equals('- milk\n- '));
      expect(enter('- [x] milk')?.text, equals('- [x] milk\n- [ ] '));
      expect(enter('  1. first')?.text, equals('  1. first\n  2. '));
    });

    test('an empty item ends the list', () {
      final result = enter('- milk\n- ');
      expect(result?.text, equals('- milk\n'));
      expect(result?.cursor, equals('- milk\n'.length));
    });

    test('a plain line is left alone', () {
      expect(enter('Just text'), isNull);
    });
  });

  group('the toolbar toggles', () {
    test('a second press takes the marker off', () {
      final once = togglePrefix('milk', 0, 0, '- ');
      expect(once.text, equals('- milk'));
      expect(togglePrefix(once.text, 2, 2, '- ').text, equals('milk'));
    });

    test('a different marker is replaced, not stacked', () {
      expect(togglePrefix('- milk', 0, 0, '- [ ] ').text, equals('- [ ] milk'));
      expect(togglePrefix('> quote', 0, 0, '## ').text, equals('## quote'));
      expect(togglePrefix('- [ ] milk', 0, 0, '- ').text, equals('- milk'));
    });

    test('works on every selected line', () {
      expect(togglePrefix('a\nb', 0, 3, '- ').text, equals('- a\n- b'));
    });

    // The cursor at 0 of a text starting with a newline threw a RangeError, and a
    // selection from 0 marked the second line instead of the first.
    test('at the very start of a text that starts with a newline', () {
      expect(
        togglePrefix('\nShopping', 0, 0, '- ').text,
        equals('- \nShopping'),
      );
      expect(togglePrefix('a\nb', 0, 1, '- ').text, equals('- a\nb'));
    });
  });

  // The renderer shows a quoted box and none for a bare "- [ ]" at a line end; the
  // count went the other way, and tapping "passport" ticked "tickets".
  test('boxes are counted the way the page shows them', () {
    const text = '> - [ ] passport\n- [ ] tickets\n- [ ]';
    expect(taskCount(text), equals(2));
    expect(
      toggleTask(text, 0),
      equals('> - [x] passport\n- [ ] tickets\n- [ ]'),
    );
  });
}
