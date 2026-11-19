import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/common/word_diff.dart';

void main() {
  const same = DiffKind.same;
  const added = DiffKind.added;
  const removed = DiffKind.removed;

  test('one word replaced', () {
    expect(
      diffWords('Buy milk today', 'Buy oat milk today'),
      equals([
        const DiffSegment(same, 'Buy '),
        const DiffSegment(added, 'oat '),
        const DiffSegment(same, 'milk today'),
      ]),
    );
    expect(
      diffWords('Meet at 5 pm.', 'Meet at 6 pm.'),
      equals([
        const DiffSegment(same, 'Meet at '),
        const DiffSegment(removed, '5'),
        const DiffSegment(added, '6'),
        const DiffSegment(same, ' pm.'),
      ]),
    );
  });

  test('identical texts are one unchanged segment', () {
    expect(
      diffWords('Router', 'Router'),
      equals([const DiffSegment(same, 'Router')]),
    );
  });

  test('from nothing everything is added', () {
    expect(
      diffWords('', 'New text'),
      equals([const DiffSegment(added, 'New text')]),
    );
  });
}
