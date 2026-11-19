import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hiwiski_tokens.dart';
import '../../links/view/reference_autocomplete.dart';
import '../rich_text_view_model.dart';
import 'markdown_text_controller.dart';
import 'markdown_toolbar.dart';

/// The field a Markdown text is written in — a page, a task's description, an event's
/// note: formatted, as it will read, or as its source in mono
/// ([MarkdownTextController]), starting as the member chose in Account → Customize.
///
/// Around it what writing Markdown needs either way: `#` suggesting items, Tab
/// indenting a line, lists going on with Enter, and Ctrl/⌘+B and +I for bold and
/// italic. The bar ([MarkdownToolbar]) is placed by the screen — above the field, or
/// docked on the keyboard.
class MarkdownField extends ConsumerWidget {
  const MarkdownField({
    super.key,
    required this.controller,
    required this.focusNode,
    this.fieldKey,
    this.decoration = const InputDecoration(),
    this.minLines = 3,
    this.autofocus = false,
    this.dockedBelow = 0,
  });

  final MarkdownTextController controller;
  final FocusNode focusNode;
  final Key? fieldKey;
  final InputDecoration decoration;
  final int minLines;
  final bool autofocus;

  /// What is docked above the keyboard below the `#` suggestions
  /// ([ReferenceAutocomplete.dockedBelow]).
  final double dockedBelow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    controller.defaultFormatted = ref.watch(richTextModeViewModelProvider);
    return ValueListenableBuilder<bool?>(
      valueListenable: controller.chosen,
      builder: (context, _, _) => ReferenceAutocomplete(
        controller: controller,
        focusNode: focusNode,
        indentWithTab: true,
        dockedBelow: dockedBelow,
        child: CallbackShortcuts(
          bindings: {
            for (final (key, marker) in _wraps) ...{
              SingleActivator(key, control: true): () =>
                  wrapSelection(controller, marker),
              SingleActivator(key, meta: true): () =>
                  wrapSelection(controller, marker),
            },
          },
          child: TextField(
            key: fieldKey,
            controller: controller,
            focusNode: focusNode,
            autofocus: autofocus,
            inputFormatters: [
              ListContinuation(),
              FormattedBackspace(controller),
            ],
            maxLines: null,
            minLines: minLines,
            // Formatted, the text is set like the read page; as source, in mono —
            // Markdown's columns line up, and it says: this is the source.
            style: controller.formatted
                ? context.tokens.text.prose
                : context.tokens.text.monoSmall,
            decoration: decoration,
          ),
        ),
      ),
    );
  }
}

/// The keys that wrap the selection in a marker, with Ctrl or ⌘.
final _wraps = [
  (LogicalKeyboardKey.keyB, '**'),
  (LogicalKeyboardKey.keyI, '*'),
];
