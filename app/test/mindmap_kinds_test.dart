import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/domain/wiki/mindmap_kinds.dart';
import 'package:hiwiski/features/wiki/view/mindmap/mindmap_element.dart';

/// **An element's kind is described once for each part of the app**: what it
/// allows ([MindmapKind]), how it is drawn ([MindmapKindLook]) and how it is made on
/// the map's screen (`mindmap_screen_test.dart`). A kind described in one and
/// forgotten in another is drawn as a placeholder or offered nothing.
void main() {
  const unknown = 'SOMETHING_NEWER';

  test('the kinds this app knows', () {
    expect(
      mindmapKinds,
      containsAll([
        MindmapKinds.plain,
        MindmapKinds.note,
        MindmapKinds.image,
        MindmapKinds.link,
        MindmapKinds.member,
        MindmapKinds.drawing,
      ]),
    );
    expect(knowsMindmapKind(unknown), isFalse);
  });

  test('every kind it knows is drawn as itself, not as a placeholder', () {
    final placeholder = MindmapElementView.lookOf(unknown);
    for (final kind in mindmapKinds) {
      expect(
        MindmapElementView.lookOf(kind),
        isNot(same(placeholder)),
        reason: kind,
      );
    }
  });

  test('a kind it does not know is kept, moved and coloured, nothing more', () {
    final kind = mindmapKindOf(unknown);
    expect(kind.surface, isTrue);
    expect(kind.coloured, isTrue);
    expect(kind.editable, isFalse);
    expect(kind.texted, isFalse);
    expect(kind.outlined, isFalse);
  });
}
