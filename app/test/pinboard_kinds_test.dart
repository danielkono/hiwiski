import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/domain/wiki/pinboard_kinds.dart';
import 'package:hiwiski/domain/wiki/pinboard_shapes.dart';
import 'package:hiwiski/features/wiki/view/pinboard/pinboard_element.dart';

/// **An element's kind and its outline are described once for each part of the
/// app**: what a kind allows ([PinboardKind]), how it is drawn ([PinboardKindLook]) and
/// how it is made on the map's screen (`pinboard_screen_test.dart`); an outline's
/// geometry ([PinboardShape]) and its look ([PinboardShapeLook]). One described in one
/// part and forgotten in another is drawn as a placeholder or offered nothing.
void main() {
  const unknown = 'SOMETHING_NEWER';

  test('the kinds this app knows', () {
    expect(
      pinboardKinds,
      containsAll([
        PinboardKinds.plain,
        PinboardKinds.note,
        PinboardKinds.image,
        PinboardKinds.link,
        PinboardKinds.member,
        PinboardKinds.drawing,
      ]),
    );
    expect(knowsPinboardKind(unknown), isFalse);
  });

  test('every kind it knows is drawn as itself, not as a placeholder', () {
    final placeholder = PinboardElementView.lookOf(unknown);
    for (final kind in pinboardKinds) {
      expect(
        PinboardElementView.lookOf(kind),
        isNot(same(placeholder)),
        reason: kind,
      );
    }
  });

  test('a kind it does not know is kept, moved and coloured, nothing more', () {
    final kind = pinboardKindOf(unknown);
    expect(kind.surface, isTrue);
    expect(kind.coloured, isTrue);
    expect(kind.editable, isFalse);
    expect(kind.texted, isFalse);
    expect(kind.outlined, isFalse);
  });

  test('every outline it offers is drawn and named as itself', () async {
    final l = await L.delegate.load(const Locale('en'));
    final fallback = PinboardElementView.shapeLookOf(unknown);
    final names = <String>{};
    for (final shape in pinboardShapes) {
      expect(knowsPinboardShape(shape), isTrue, reason: shape);
      final look = PinboardElementView.shapeLookOf(shape);
      if (shape != PinboardShapes.rounded) {
        expect(look, isNot(same(fallback)), reason: shape);
      }
      expect(names.add(look.name(l)), isTrue, reason: '$shape named twice');
    }
    expect(knowsPinboardShape(unknown), isFalse);
  });
}
