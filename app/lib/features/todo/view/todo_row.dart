import 'package:flutter/material.dart';

import '../../../core/common/wire.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../domain/todo/quick_entry.dart';
import '../../../domain/todo/todo_items.dart';
import '../../../core/ui/delete_hold_button.dart';
import '../../../core/ui/item_draggable.dart';
import '../../../core/ui/renamable_row.dart';
import '../../../core/ui/renamable_title.dart';
import '../../../core/ui/row_chevron.dart';
import 'todo_keys.dart';
import 'removable_row.dart';

/// A row with checkbox, title and mono number, with the meta line below
/// ("Tue, 29.09. · Ben · every week") — on a shopping list "**2 l** Milch".
///
/// **The checkbox is a target of its own (44×44)** — otherwise whoever wants to check
/// off opens the detail. In a [RenamableRow], held, the title is
/// edited in place.
class TodoRowTile extends StatelessWidget {
  const TodoRowTile({
    super.key,
    required this.todo,
    required this.shopping,
    required this.onOpen,
    this.onToggle,
    this.meta = '',
    this.deletable = false,
  });

  final Todo todo;
  final bool shopping;

  /// `null` when the box may not be ticked — archived, or *read* only.
  final VoidCallback? onToggle;
  final VoidCallback onOpen;

  /// The meta line; empty on a shopping list.
  final String meta;

  /// Whether the row shows the delete symbol — held, it deletes the task; the row
  /// has to sit in a [RemovableRow].
  final bool deletable;

  bool get _done => todo.status == TodoStatuses.done;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final tokens = context.tokens;
    final scheme = context.scheme;
    final editing = RenamableRow.editing(context);
    // While the title is a field, a tap beside it does not open the task.
    final VoidCallback? open = editing ? null : onOpen;
    final hold = ItemDraggable.takesLongPress(context)
        ? null
        : RenamableRow.maybeOf(context)?.edit;

    final box = SizedBox.square(
      dimension: HiwiskiMetrics.minTapTarget,
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(
          _done ? HiwiskiSymbols.checkBox : HiwiskiSymbols.checkBoxOutlineBlank,
          // FILL 1 when done.
          fill: _done ? 1 : 0,
          size: HiwiskiMetrics.icon26,
          color: _done ? scheme.primary : scheme.onSurfaceVariant,
        ),
        onPressed: onToggle,
        tooltip: l.todoDone,
      ),
    );

    if (shopping) {
      final entry = QuickEntry(
        title: todo.title,
        amount: todo.amount,
        unit: todo.unit,
      );
      final style = tokens.text.shoppingLine.copyWith(
        decoration: _done ? TextDecoration.lineThrough : null,
        color: _done ? scheme.outline : null,
      );
      // "**2 l** Milch" — the amount in bold; done items grey and struck through.
      return InkWell(
        onTap: open,
        onLongPress: hold,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: HiwiskiMetrics.listRowHeight,
          ),
          child: Row(
            spacing: HiwiskiMetrics.space10,
            children: [
              box,
              Expanded(
                // Edited as it is entered: "2 l Milch".
                child: RenamableTitle(
                  fieldKey: TodoKeys.titleField(todo.id),
                  text: entry.amount == null
                      ? todo.title
                      : '${entry.amountLabel} ${todo.title}',
                  style: style,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        // Even without a unit: "**3** Paprika", "**10** Eier".
                        if (entry.amount != null)
                          TextSpan(
                            text: '${entry.amountLabel} ',
                            style: tokens.text.shoppingAmount,
                          ),
                        TextSpan(text: todo.title),
                      ],
                    ),
                    style: style,
                  ),
                ),
              ),
              if (deletable)
                DeleteHoldButton(holdKey: TodoKeys.deleteTodo(todo.id)),
              // An entry opens a page as a task does, and says so the same way.
              const RowChevron(),
            ],
          ),
        ),
      );
    }

    final titleStyle = context.texts.bodyLarge?.copyWith(
      fontWeight: .w500,
      // Strikethrough **and** a filled checkbox: colour is never the only carrier.
      decoration: _done ? TextDecoration.lineThrough : null,
      color: _done ? scheme.onSurfaceVariant : null,
    );
    return InkWell(
      onTap: open,
      onLongPress: hold,
      child: ConstrainedBox(
        // `minHeight` and not `height`: text sizes scale via
        // `MediaQuery.textScaler`, and a fixed height clips with a large
        // system font (pitfall 3).
        constraints: const BoxConstraints(
          minHeight: HiwiskiMetrics.listRowHeightTall,
        ),
        child: Padding(
          padding: const .symmetric(vertical: HiwiskiMetrics.space6),
          child: Row(
            children: [
              box,
              const SizedBox(width: HiwiskiMetrics.space8),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  mainAxisSize: .min,
                  children: [
                    RenamableTitle(
                      fieldKey: TodoKeys.titleField(todo.id),
                      text: todo.title,
                      style: titleStyle,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: todo.title, style: titleStyle),
                            if (todo.entityKey != null)
                              TextSpan(
                                text: '  ${todo.entityKey}',
                                style: tokens.text.entityKey,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (meta.isNotEmpty)
                      Padding(
                        padding: const .only(top: HiwiskiMetrics.space4),
                        child: Text(
                          meta,
                          style: context.texts.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (deletable)
                DeleteHoldButton(holdKey: TodoKeys.deleteTodo(todo.id)),
              const RowChevron(),
            ],
          ),
        ),
      ),
    );
  }
}
