import 'package:flutter/widgets.dart';

import '../../domain/wiki/markdown_editing.dart';

/// Inserts at the cursor — the same rule the bar itself uses.
///
/// One rule for the Markdown bar, the editor and the comments: whatever the link
/// picker returns is inserted exactly like a checkbox or a quote, and two insertion
/// rules would be one too many.
void insertAtCursor(TextEditingController controller, String text) {
  final selection = controller.selection;
  if (!selection.isValid) {
    controller.text = '${controller.text}$text';
    return;
  }
  controller.value = controller.value.copyWith(
    text: controller.text.replaceRange(selection.start, selection.end, text),
    selection: TextSelection.collapsed(offset: selection.start + text.length),
  );
}

const _newline = '\n';

/// Indents — or, with [outdent], takes back — every line the selection touches by one
/// step: what Tab and Shift+Tab do in a Markdown text, where a nested list item is
/// nothing but a line pushed in. The step is the one the list above needs
/// ([listIndentSteps]); every line moves by the first line's step, so a block keeps its
/// shape. The selection keeps covering what it covered.
void indentSelection(TextEditingController controller, {bool outdent = false}) {
  final selection = controller.selection;
  if (!selection.isValid) return;
  final text = controller.text;
  final start = selection.start;
  int end = selection.end;
  // A selection that ends right after a line break does not touch the next line.
  if (end > start && text[end - 1] == _newline) end--;
  final lineStart = start == 0 ? 0 : text.lastIndexOf(_newline, start - 1) + 1;
  final lines = text.substring(lineStart, end).split(_newline);
  final steps = listIndentSteps(
    lineStart == 0
        ? const []
        : text.substring(0, lineStart - 1).split(_newline),
    lines.first,
  );
  final step = outdent ? steps.outdent : steps.indent;

  int firstDelta = 0;
  int total = 0;
  final changed = <String>[];
  for (final (index, line) in lines.indexed) {
    final String next;
    if (!outdent) {
      // An empty line stays empty in a block: trailing spaces would be noise.
      next = line.isEmpty && lines.length > 1 ? line : '${' ' * step}$line';
    } else {
      final spaces = line.length - line.trimLeft().length;
      next = line.substring(spaces < step ? spaces : step);
    }
    final delta = next.length - line.length;
    if (index == 0) firstDelta = delta;
    total += delta;
    changed.add(next);
  }

  final newStart = start + firstDelta < lineStart
      ? lineStart
      : start + firstDelta;
  final newEnd = selection.end + total;
  controller.value = controller.value.copyWith(
    text: text.replaceRange(lineStart, end, changed.join(_newline)),
    selection: TextSelection(
      baseOffset: selection.baseOffset <= selection.extentOffset
          ? newStart
          : newEnd,
      extentOffset: selection.baseOffset <= selection.extentOffset
          ? newEnd
          : newStart,
    ),
  );
}
