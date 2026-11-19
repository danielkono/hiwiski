import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/wiki/page_images.dart';

/// **Images in a page's text** — on lines of their own, consecutive ones a group.
void main() {
  test('consecutive image lines are one group', () {
    expect(
      pageSegments(
        'Before\n\n${imageMarkdown('a')}\n${imageMarkdown('b')}\n\nAfter',
      ),
      equals([
        const TextSegment('Before\n'),
        const ImageGroup(['a', 'b']),
        const TextSegment('\nAfter'),
      ]),
    );
  });

  test('a blank line starts another group', () {
    expect(
      pageSegments('${imageMarkdown('a')}\n\n${imageMarkdown('b')}'),
      equals([
        const ImageGroup(['a']),
        const ImageGroup(['b']),
      ]),
    );
  });

  test('several images on one line belong together', () {
    expect(
      pageSegments('${imageMarkdown('a')} ${imageMarkdown('b')}'),
      equals([
        const ImageGroup(['a', 'b']),
      ]),
    );
  });

  test('an image inside a code block stays text', () {
    final code = '```\n${imageMarkdown('a')}\n```';
    expect(pageSegments(code), equals([TextSegment(code)]));
  });

  test('an image within a sentence stays text', () {
    final line = 'See ${imageMarkdown('a')} here';
    expect(pageSegments(line), equals([TextSegment(line)]));
  });

  test('inserting puts the images on lines of their own', () {
    expect(
      imagesInsertion('ab', 1, ['x', 'y']),
      equals('\n${imageMarkdown('x')}\n${imageMarkdown('y')}\n'),
    );
    expect(imagesInsertion('a\n', 2, ['x']), equals(imageMarkdown('x')));
  });
}
