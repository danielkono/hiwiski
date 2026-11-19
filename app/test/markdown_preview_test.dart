import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/links/link_text.dart';
import 'package:hiwiski/domain/wiki/markdown_editing.dart';
import 'package:hiwiski/domain/wiki/markdown_preview.dart';

/// The formatted editor: what each character of the source is drawn as, where the
/// cursor may go, and what Backspace does.
void main() {
  /// The characters of [text] that are drawn, with every hidden one left out and each
  /// widget as a letter of its own: `•` a bullet, `☐`/`☑` a box, `|` a quote bar, `@` a
  /// chip, `▣` an image.
  String drawn(String text, {int start = -1, int end = -1}) {
    final out = StringBuffer();
    for (final run in MarkdownPreview.of(text).runs(start: start, end: end)) {
      switch (run.widget) {
        case PreviewBullet():
          out.write('•');
        case PreviewTaskBox(:final checked):
          out.write(checked ? '☑' : '☐');
        case PreviewQuoteBar():
          out.write('|');
        case PreviewReference():
          out.write('@');
        case PreviewImage():
          out.write('▣');
        case null:
          if (run.flags & PreviewFlags.hidden == 0) {
            out.write(text.substring(run.start, run.end));
          }
      }
    }
    return out.toString();
  }

  int flagsAt(String text, int offset, {int start = -1, int end = -1}) =>
      MarkdownPreview.of(text)
          .runs(start: start, end: end)
          .firstWhere((run) => run.start <= offset && offset < run.end)
          .flags;

  group('drawing', () {
    test('the runs cover the text, in order', () {
      const text = '# Title\n\n- **a** and *b*\n- [ ] c\n> quote';
      final runs = MarkdownPreview.of(text).runs();
      expect(runs.first.start, equals(0));
      expect(runs.last.end, equals(text.length));
      for (int i = 1; i < runs.length; i++) {
        expect(runs[i].start, equals(runs[i - 1].end));
      }
    });

    test('a heading hides its hashes and is drawn at its level', () {
      expect(drawn('## Packing'), equals('Packing'));
      expect(PreviewFlags.headingOf(flagsAt('## Packing', 4)), equals(2));
      // "#TD-14" is a reference, "#" alone a beginning: neither is a heading.
      expect(PreviewFlags.headingOf(flagsAt('#hash', 1)), equals(0));
    });

    test('bold and italic hide their markers until the cursor is at them', () {
      const text = 'a **bold** and *it* z';
      expect(drawn(text), equals('a bold and it z'));
      expect(flagsAt(text, 4) & PreviewFlags.bold, isNot(0));
      expect(flagsAt(text, 16) & PreviewFlags.italic, isNot(0));
      // The cursor inside the bold: its markers show, faded; the italic's stay away.
      expect(drawn(text, start: 5, end: 5), equals('a **bold** and it z'));
      expect(
        flagsAt(text, 2, start: 5, end: 5) & PreviewFlags.marker,
        isNot(0),
      );
    });

    test('bold and italic at once', () {
      const text = '***both***';
      expect(drawn(text), equals('both'));
      final flags = flagsAt(text, 4);
      expect(flags & PreviewFlags.bold, isNot(0));
      expect(flags & PreviewFlags.italic, isNot(0));
    });

    test('an escaped star stays a star, code stays as typed', () {
      expect(drawn(r'2 \* 3 = 6'), equals(r'2 \* 3 = 6'));
      expect(drawn('run `a *b* c`'), equals('run a *b* c'));
      expect(flagsAt('run `a *b* c`', 7) & PreviewFlags.italic, equals(0));
    });

    test('a link shows its label, the address only at the cursor', () {
      const text = 'see [the site](https://example.org) now';
      expect(drawn(text), equals('see the site now'));
      expect(flagsAt(text, 6) & PreviewFlags.link, isNot(0));
      expect(drawn(text, start: 6, end: 6), equals(text));
    });

    test('an image from elsewhere reads as a link to it', () {
      const text = 'see ![google](https://google.com) now';
      expect(drawn(text), equals('see google now'));
      expect(flagsAt(text, 7) & PreviewFlags.link, isNot(0));
      expect(drawn(text, start: 7, end: 7), equals(text));
      // Without a label the address is what there is to show.
      expect(
        drawn('![](https://google.com)'),
        equals('![](https://google.com)'),
      );
    });

    test('lists: a bullet, a number, a box', () {
      expect(drawn('- milk'), equals('• milk'));
      expect(drawn('1. milk'), equals('1. milk'));
      expect(drawn('- [ ] milk\n- [x] eggs'), equals('☐ milk\n☑ eggs'));
      expect(drawn('1. [ ] milk'), equals('1. ☐ milk'));
    });

    test('nested bullets know their depth', () {
      final runs = MarkdownPreview.of('- a\n  - b\n    - c\n- d').runs();
      final depths = [
        for (final run in runs)
          if (run.widget case PreviewBullet(:final depth)) depth,
      ];
      expect(depths, equals([0, 1, 2, 0]));
    });

    test('the boxes are counted as the toggle counts them', () {
      const text = '- [ ] a\n```\n- [ ] not a box\n```\n> - [x] b\n- [ ] c';
      final boxes = [
        for (final run in MarkdownPreview.of(text).runs())
          if (run.widget case PreviewTaskBox(:final index)) index,
      ];
      expect(boxes, equals([0, 1, 2]));
      expect(taskCount(text), equals(3));
    });

    test('a quote shows a bar, a code block stays as typed', () {
      expect(drawn('> said'), equals('| said'));
      expect(drawn('```\n**x**\n```'), equals('```\n**x**\n```'));
    });

    test('links to items and images are one widget each', () {
      const id = '0f8fad5b-d9cb-469f-a165-70867728950e';
      const text = 'see #TD-14 and [Packing](hiwiski://wiki_page/$id)';
      expect(drawn(text), equals('see @ and @'));
      final chips = [
        for (final run in MarkdownPreview.of(text).runs())
          if (run.widget case PreviewReference(:final part)) part.reference,
      ];
      expect(
        chips,
        equals([
          const KeyReference('TD-14'),
          const UriReference('WIKI_PAGE', id),
        ]),
      );
      expect(drawn('![](hiwiski-image:abc-1)'), equals('▣'));
    });
  });

  group('the cursor', () {
    test('does not go into a line prefix', () {
      final preview = MarkdownPreview.of('text\n## Head');
      // A tap at the left edge of the heading lands at its text.
      expect(preview.snap(0, 5), equals(8));
      // Left out of the heading's text: the end of the line above.
      expect(preview.snap(8, 7), equals(4));
      // Anywhere else stays.
      expect(preview.snap(9, 10), equals(10));
    });

    test('does not go into a chip', () {
      final preview = MarkdownPreview.of('a #TD-14 b');
      expect(preview.snap(8, 7), equals(2));
      expect(preview.snap(2, 3), equals(8));
    });
  });

  group('Backspace', () {
    test('at the start of a list item makes it text', () {
      final preview = MarkdownPreview.of('- milk');
      expect(preview.backspace(2), equals((text: 'milk', cursor: 0)));
    });

    test('at the start of a box takes the box', () {
      final preview = MarkdownPreview.of('- [ ] milk');
      expect(preview.backspace(6), equals((text: 'milk', cursor: 0)));
    });

    test('at the start of a nested item moves it out a level', () {
      final preview = MarkdownPreview.of('- a\n  - b');
      expect(preview.backspace(8), equals((text: '- a\n- b', cursor: 6)));
    });

    test('at the start of a heading makes it text', () {
      final preview = MarkdownPreview.of('## Head');
      expect(preview.backspace(3), equals((text: 'Head', cursor: 0)));
    });

    test('in a quoted list takes the list marker first', () {
      final preview = MarkdownPreview.of('> - a');
      expect(preview.backspace(4), equals((text: '> a', cursor: 2)));
    });

    test('after a picked link takes the link', () {
      const id = '0f8fad5b-d9cb-469f-a165-70867728950e';
      const text = 'a [Packing](hiwiski://wiki_page/$id)';
      final preview = MarkdownPreview.of(text);
      expect(preview.backspace(text.length), equals((text: 'a ', cursor: 2)));
    });

    test('after a typed number takes one digit, as typed', () {
      expect(MarkdownPreview.of('a #TD-14').backspace(8), isNull);
    });

    test('in ordinary text does nothing special', () {
      expect(MarkdownPreview.of('milk').backspace(2), isNull);
      expect(MarkdownPreview.of('- milk').backspace(4), isNull);
    });
  });

  group('toggleWrap', () {
    test('wraps, and takes it back', () {
      final on = toggleWrap('Soup', 0, 4, '**');
      expect(on, equals((text: '**Soup**', start: 2, end: 6)));
      final off = toggleWrap(on.text, on.start, on.end, '**');
      expect(off, equals((text: 'Soup', start: 0, end: 4)));
    });

    test('italic on bold adds a star instead of eating into the bold', () {
      final both = toggleWrap('**Soup**', 2, 6, '*');
      expect(both.text, equals('***Soup***'));
      final back = toggleWrap(both.text, both.start, both.end, '*');
      expect(back.text, equals('**Soup**'));
    });

    test('a selection holding its markers loses them', () {
      expect(toggleWrap('**Soup**', 0, 8, '**').text, equals('Soup'));
    });

    test('an empty pair around the cursor comes out', () {
      final pair = toggleWrap('a ', 2, 2, '**');
      expect(pair, equals((text: 'a ****', start: 4, end: 4)));
      expect(toggleWrap(pair.text, 4, 4, '**').text, equals('a '));
    });
  });
}
