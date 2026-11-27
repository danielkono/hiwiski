import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/ui/text_insertion.dart';
import '../../../domain/common/item_ref.dart';
import '../../../domain/wiki/page_images.dart';
import '../../links/view/link_picker.dart';
import '../rich_text_view_model.dart';
import 'image_files.dart';
import 'markdown_field.dart';
import 'markdown_text_controller.dart';
import 'markdown_toolbar.dart';

/// Writing a text the way a wiki page is written: the bar above it — formatted or
/// Markdown, headings, bold, lists, boxes, a link from the picker, images — and the
/// field ([MarkdownField]). For a task's description, a list's and an event's note;
/// images go onto [carrier].
class RichTextEditor extends ConsumerStatefulWidget {
  const RichTextEditor({
    super.key,
    required this.controller,
    this.carrier,
    this.focusNode,
    this.fieldKey,
    this.label,
    this.hint,
    this.minLines = 6,
    this.autofocus = false,
    this.scrollsField = false,
  });

  final MarkdownTextController controller;

  /// The item the images hang on; `null` while it does not exist yet — a new event —
  /// and then there is no image button.
  final ItemRef? carrier;
  final FocusNode? focusNode;
  final Key? fieldKey;
  final String? label;
  final String? hint;
  final int minLines;
  final bool autofocus;

  /// Whether the field scrolls under the bar instead of growing with the text — in a
  /// sheet that does not scroll itself, so the bar stays in view however long the
  /// text gets. The editor then takes the height it is given.
  final bool scrollsField;

  @override
  ConsumerState<RichTextEditor> createState() => _RichTextEditorState();
}

class _RichTextEditorState extends ConsumerState<RichTextEditor> {
  FocusNode? _ownFocus;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void dispose() {
    _ownFocus?.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    final markdown = await showLinkPicker(context);
    if (markdown != null) insertAtCursor(widget.controller, markdown);
    // The picker took the focus; the text gets it back either way.
    if (mounted) _focus.requestFocus();
  }

  /// Pictures into the text: picked, kept on the device for the carrier, and put at
  /// the cursor on lines of their own — several at once are one group, shown as a
  /// stack. They go up with the sync; nothing here waits for the server.
  Future<void> _images(ItemRef carrier) async {
    final l = L.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ids = await addRichImagesMutation.run(ref, (tsx) async {
        final viewModel = tsx.get(richTextViewModelProvider(carrier).notifier);
        final files = await pickImageFiles();
        return files.isEmpty ? const <String>[] : viewModel.addImages(files);
      });
      if (ids.isEmpty || !mounted) return;
      final controller = widget.controller;
      final at = controller.selection.isValid
          ? controller.selection.start
          : controller.text.length;
      insertAtCursor(controller, imagesInsertion(controller.text, at, ids));
    } on Object catch (error) {
      // Not the server's answer: a picture that could not be read. It used to end
      // the attempt without a word.
      debugPrint('hiwiski: images not added: $error');
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l.wikiImagesFailed)));
    }
    if (mounted) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final carrier = widget.carrier;
    // Watched so that the carrier's ViewModel lives while the editor does — the
    // upload runs through it.
    if (carrier != null) ref.watch(richTextViewModelProvider(carrier));
    final field = MarkdownField(
      controller: widget.controller,
      focusNode: _focus,
      fieldKey: widget.fieldKey,
      autofocus: widget.autofocus,
      minLines: widget.minLines,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        alignLabelWithHint: true,
      ),
    );
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: widget.scrollsField ? .min : .max,
      children: [
        MarkdownToolbar(
          controller: widget.controller,
          focusNode: _focus,
          onLink: _link,
          onImages: carrier == null
              ? null
              // Through the controller: saving waits until they are in the text.
              : () => widget.controller.addImages(() => _images(carrier)),
          imagesBusy: ref.watch(addRichImagesMutation).isPending,
        ),
        const SizedBox(height: HiwiskiMetrics.space4),
        if (widget.scrollsField)
          Flexible(child: SingleChildScrollView(child: field))
        else
          field,
      ],
    );
  }
}
