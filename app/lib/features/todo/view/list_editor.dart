import 'package:flutter/material.dart';

import '../../../components/rich_text/view/rich_text_editor.dart';
import '../../../components/rich_text/view/markdown_text_controller.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../domain/common/item_ref.dart';
import '../../../domain/todo/todo_items.dart';
import 'todo_keys.dart';

/// A list's name and description as fields, in place of its intro — "Edit" opens it
/// on the page itself, not in a sheet over it. Below the fields what is done to the
/// whole list at once: untick everything, delete what is ticked off.
///
/// "Save" and "Cancel" are the header's, where "Edit" was: the screen calls
/// [ListEditorState.save] from there.
///
/// Passive: it hands back what was typed; the screen's ViewModel writes it.
class ListEditor extends StatefulWidget {
  const ListEditor({
    super.key,
    required this.list,
    required this.done,
    required this.onSave,
    this.onUntickAll,
    this.onDeleteDone,
  });

  final TodoList list;

  /// How many entries are ticked off — what the two actions would touch.
  final int done;

  /// The name and description, trimmed; an empty name keeps the old one.
  final void Function({required String name, required String? description})
  onSave;

  /// `null` where the list has no boxes to untick — a board.
  final VoidCallback? onUntickAll;
  final VoidCallback? onDeleteDone;

  @override
  State<ListEditor> createState() => ListEditorState();
}

class ListEditorState extends State<ListEditor> {
  late final _name = TextEditingController(text: widget.list.name);
  late final _description = MarkdownTextController(
    text: widget.list.description ?? '',
  );
  final _descriptionFocus = FocusNode();

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  /// Hands what was typed to the screen — the header's "Save".
  void save() {
    final description = _description.text.trim();
    widget.onSave(
      name: _name.text.trim(),
      description: description.isEmpty ? null : description,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final onUntickAll = widget.onUntickAll;
    final onDeleteDone = widget.onDeleteDone;
    return Padding(
      // The room above is the first field's label's, which reaches over the field.
      padding: const .only(
        top: HiwiskiMetrics.space8,
        bottom: HiwiskiMetrics.space16,
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          TextField(
            key: TodoKeys.listName,
            controller: _name,
            autofocus: true,
            textInputAction: .next,
            decoration: InputDecoration(labelText: l.todoListName),
            onSubmitted: (_) => _descriptionFocus.requestFocus(),
          ),
          const SizedBox(height: HiwiskiMetrics.space12),
          // Written like a wiki page: Markdown with the insert bar, `#` suggesting
          // items, images onto the list.
          RichTextEditor(
            controller: _description,
            focusNode: _descriptionFocus,
            carrier: ItemRef.todoList(widget.list.id),
            fieldKey: TodoKeys.listDescription,
            label: l.listDescription,
            hint: l.linkHintDescription,
            minLines: 3,
          ),
          if (onUntickAll != null || onDeleteDone != null) ...[
            const SizedBox(height: HiwiskiMetrics.space12),
            Wrap(
              spacing: HiwiskiMetrics.space8,
              runSpacing: HiwiskiMetrics.space8,
              children: [
                if (onUntickAll != null)
                  OutlinedButton.icon(
                    key: TodoKeys.listUntickAll,
                    icon: const Icon(HiwiskiSymbols.removeDone),
                    label: Text(l.listUntickAll(widget.done)),
                    onPressed: widget.done == 0 ? null : onUntickAll,
                  ),
                if (onDeleteDone != null)
                  OutlinedButton.icon(
                    key: TodoKeys.listDeleteDone,
                    icon: const Icon(HiwiskiSymbols.deleteSweep),
                    label: Text(l.listDeleteDone(widget.done)),
                    onPressed: widget.done == 0 ? null : onDeleteDone,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
