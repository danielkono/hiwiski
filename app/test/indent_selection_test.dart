import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/ui/text_insertion.dart';

TextEditingController _field(String text, int base, int extent) =>
    TextEditingController(text: text)
      ..selection = TextSelection(baseOffset: base, extentOffset: extent);

void main() {
  test('Tab pushes the line with the cursor in by two spaces', () {
    final controller = _field('- a\n- b', 6, 6);
    indentSelection(controller);
    expect(controller.text, equals('- a\n  - b'));
    expect(
      controller.selection,
      equals(const TextSelection.collapsed(offset: 8)),
    );
  });

  test('Tab on a selection indents every line it touches', () {
    final controller = _field('- a\n- b\n- c', 2, 9);
    indentSelection(controller);
    expect(controller.text, equals('  - a\n  - b\n  - c'));
  });

  test('Shift+Tab takes back up to two spaces and no more', () {
    final controller = _field('    - a\n - b', 0, 12);
    indentSelection(controller, outdent: true);
    expect(controller.text, equals('  - a\n- b'));
  });

  test('Shift+Tab on a line without indentation changes nothing', () {
    final controller = _field('- a', 1, 1);
    indentSelection(controller, outdent: true);
    expect(controller.text, equals('- a'));
    expect(
      controller.selection,
      equals(const TextSelection.collapsed(offset: 1)),
    );
  });

  test('under a numbered item a child needs three spaces', () {
    final controller = _field('1. a\n2. b', 8, 8);
    indentSelection(controller);
    expect(controller.text, equals('1. a\n   2. b'));
  });

  test('under a marker followed by two spaces, three as well', () {
    final controller = _field('-  a\n-  b', 7, 7);
    indentSelection(controller);
    expect(controller.text, equals('-  a\n   -  b'));
  });

  test('Shift+Tab goes back to the level of the item it was under', () {
    final controller = _field('1. a\n   2. b', 9, 9);
    indentSelection(controller, outdent: true);
    expect(controller.text, equals('1. a\n2. b'));
  });
}
