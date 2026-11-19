import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../domain/wiki/markdown_editing.dart';
import '../rich_text_view_model.dart';
import 'markdown_text_controller.dart';
import 'rich_text_keys.dart';

/// The bar above a text being written: heading, bold, list, box, quote, code, link,
/// images — and, for a [MarkdownTextController], the switch between writing it
/// formatted and as its Markdown, first in the row.
///
/// The text stays Markdown either way, and the bar edits it at the cursor: formatted,
/// what it inserts shows as it will read; as source, as what it is.
///
/// The bar never takes the focus from the text: it counts as part of the field
/// ([TextFieldTapRegion]), its buttons cannot be focused, and after every insert
/// [focusNode] gets the focus back. Otherwise a tap on "bold" closes the keyboard
/// and the next letter goes nowhere.
class MarkdownToolbar extends StatelessWidget {
  const MarkdownToolbar({
    super.key,
    required this.controller,
    this.focusNode,
    this.onLink,
    this.onImages,
    this.imagesBusy = false,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback? onLink;

  /// Pictures into the text at the cursor; `null` hides the button.
  final VoidCallback? onImages;

  /// Images are being chosen, read or uploaded: the button turns, and waits.
  final bool imagesBusy;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return TextFieldTapRegion(
      child: SingleChildScrollView(
        scrollDirection: .horizontal,
        child: Row(
          children: [
            if (controller case final MarkdownTextController markdown) ...[
              _ModeSwitch(controller: markdown, focusNode: focusNode),
              const SizedBox(width: HiwiskiMetrics.space4),
            ],
            _Button(
              icon: HiwiskiSymbols.title,
              tooltip: l.wikiMdHeading,
              onTap: () => _apply(() => _prefix('## ')),
            ),
            _Button(
              icon: HiwiskiSymbols.formatBold,
              tooltip: l.wikiMdBold,
              onTap: () => _apply(() => wrapSelection(controller, '**')),
            ),
            _Button(
              icon: HiwiskiSymbols.formatItalic,
              tooltip: l.wikiMdItalic,
              onTap: () => _apply(() => wrapSelection(controller, '*')),
            ),
            _Button(
              icon: HiwiskiSymbols.formatListBulleted,
              tooltip: l.wikiMdList,
              onTap: () => _apply(() => _prefix('- ')),
            ),
            _Button(
              icon: HiwiskiSymbols.checkBoxOutlineBlank,
              tooltip: l.wikiMdCheck,
              onTap: () => _apply(() => _prefix('- [ ] ')),
            ),
            _Button(
              icon: HiwiskiSymbols.formatQuote,
              tooltip: l.wikiMdQuote,
              onTap: () => _apply(() => _prefix('> ')),
            ),
            _Button(
              icon: HiwiskiSymbols.code,
              tooltip: l.wikiMdCode,
              onTap: () => _apply(() => wrapSelection(controller, '`')),
            ),
            if (onLink case final onLink?)
              _Button(
                icon: HiwiskiSymbols.link,
                tooltip: l.wikiLinkInsert,
                onTap: onLink,
              ),
            if (onImages case final onImages?)
              imagesBusy
                  ? _Busy(
                      key: RichTextKeys.imagesBusy,
                      tooltip: l.wikiImagesUploading,
                    )
                  : _Button(
                      key: RichTextKeys.insertImages,
                      icon: HiwiskiSymbols.addPhotoAlternate,
                      tooltip: l.wikiImagesInsert,
                      onTap: onImages,
                    ),
          ],
        ),
      ),
    );
  }

  /// The edit, then the focus back into the text.
  void _apply(VoidCallback edit) {
    edit();
    focusNode?.requestFocus();
  }

  /// Puts a prefix at the start of **every** selected line — or takes it off again.
  ///
  /// Without a selection, at the start of the line the cursor is in — not at the cursor
  /// position itself: "- " in the middle of a word does not make a list. Pressing it
  /// twice used to stack it ("- - "); now it toggles (markdown_editing.dart).
  void _prefix(String prefix) {
    final text = controller.text;
    final selection = controller.selection;
    if (!selection.isValid) {
      controller.text = '$prefix$text';
      return;
    }
    final result = togglePrefix(text, selection.start, selection.end, prefix);
    controller.value = controller.value.copyWith(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.end),
    );
  }
}

/// Bold, italic, code: the marker around the selection — or off it again, when it is
/// there already ([toggleWrap]). Without a selection the markers go in with the
/// cursor between them. For the bar and for Ctrl/⌘+B and +I.
void wrapSelection(TextEditingController controller, String marker) {
  final text = controller.text;
  final selection = controller.selection;
  if (!selection.isValid) {
    controller.text = '$text$marker$marker';
    return;
  }
  final result = toggleWrap(text, selection.start, selection.end, marker);
  controller.value = controller.value.copyWith(
    text: result.text,
    selection: TextSelection(
      baseOffset: result.start,
      extentOffset: result.end,
    ),
  );
}

/// Formatted or Markdown: two buttons side by side, the one in effect filled — so it
/// shows which mode the text is in, and the other one is a tap away.
class _ModeSwitch extends ConsumerWidget {
  const _ModeSwitch({required this.controller, this.focusNode});

  final MarkdownTextController controller;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    controller.defaultFormatted = ref.watch(richTextModeViewModelProvider);
    final l = L.of(context);
    return ValueListenableBuilder<bool?>(
      valueListenable: controller.chosen,
      builder: (context, _, _) {
        final formatted = controller.formatted;
        void toggle() {
          controller.toggleFormatted();
          focusNode?.requestFocus();
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            color: context.scheme.surfaceContainerHigh,
            borderRadius: const .all(.circular(HiwiskiMetrics.radiusPill)),
          ),
          child: Row(
            mainAxisSize: .min,
            children: [
              _ModeButton(
                key: RichTextKeys.showFormatted,
                icon: HiwiskiSymbols.wysiwyg,
                tooltip: l.editorShowFormatted,
                selected: formatted,
                onTap: formatted ? null : toggle,
              ),
              _ModeButton(
                key: RichTextKeys.showMarkdown,
                icon: HiwiskiSymbols.markdown,
                tooltip: l.editorShowMarkdown,
                selected: !formatted,
                onTap: formatted ? toggle : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;

  /// `null` for the mode in effect: tapping it again changes nothing.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ExcludeFocus(
    child: IconButton(
      isSelected: selected,
      icon: Icon(icon, size: HiwiskiMetrics.icon20),
      selectedIcon: Icon(icon, size: HiwiskiMetrics.icon20, fill: 1),
      tooltip: tooltip,
      // The mode in effect is not a disabled button: it stays drawn as chosen.
      onPressed: onTap ?? () {},
      style: IconButton.styleFrom(
        backgroundColor: selected ? context.scheme.secondaryContainer : null,
        foregroundColor: selected
            ? context.scheme.onSecondaryContainer
            : context.scheme.onSurfaceVariant,
      ),
      constraints: const BoxConstraints(
        minWidth: HiwiskiMetrics.minTapTarget,
        minHeight: HiwiskiMetrics.minTapTarget,
      ),
    ),
  );
}

class _Button extends StatelessWidget {
  const _Button({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ExcludeFocus(
    child: IconButton(
      icon: Icon(icon, size: HiwiskiMetrics.icon20),
      tooltip: tooltip,
      onPressed: onTap,
      constraints: const BoxConstraints(
        minWidth: HiwiskiMetrics.minTapTarget,
        minHeight: HiwiskiMetrics.minTapTarget,
      ),
    ),
  );
}

/// In place of a button while what it started runs.
class _Busy extends StatelessWidget {
  const _Busy({super.key, required this.tooltip});

  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      label: tooltip,
      child: const SizedBox.square(
        dimension: HiwiskiMetrics.minTapTarget,
        child: Center(
          child: SizedBox.square(
            dimension: HiwiskiMetrics.icon20,
            child: CircularProgressIndicator(
              strokeWidth: HiwiskiMetrics.strokeBold,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Enter in a list carries the marker on to the next line; Enter on an empty item ends
/// the list (markdown_editing.dart).
class ListContinuation extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cursor = newValue.selection.baseOffset;
    final oneNewLine =
        newValue.selection.isCollapsed &&
        newValue.text.length == oldValue.text.length + 1 &&
        cursor > 0 &&
        newValue.text[cursor - 1] == '\n';
    if (!oneNewLine) return newValue;
    final continued = continueList(newValue.text, cursor);
    if (continued == null) return newValue;
    return TextEditingValue(
      text: continued.text,
      selection: TextSelection.collapsed(offset: continued.cursor),
    );
  }
}
