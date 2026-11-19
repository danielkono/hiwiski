import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/tags/tag.dart';

/// **The filter bar shows the tags that matter to this member first** — the ones used
/// often and lately. With many tags it used to grow into a block above the content.
void main() {
  Tag tag(String id) =>
      .new(id: id, ownerId: 'anna', version: 1, name: id, colorToken: 'BLUE');

  List<String> ranked(List<String> uses) => [
    for (final t in rankTags([
      tag('Garden'),
      tag('Kids'),
      tag('School'),
      tag('Work'),
    ], uses))
      t.id,
  ];

  test('without any use, by name', () {
    expect(ranked(const []), equals(['Garden', 'Kids', 'School', 'Work']));
  });

  test('a tag used often stays ahead of one used once just now', () {
    expect(
      ranked(['Work', 'Kids', 'Kids', 'Kids', 'Kids']).take(2),
      equals(['Kids', 'Work']),
    );
  });

  test('between two used equally often, the more recent one leads', () {
    expect(
      ranked(['School', 'Garden', 'School', 'Garden']).take(2),
      equals(['School', 'Garden']),
    );
  });
}
