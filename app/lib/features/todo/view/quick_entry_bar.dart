import 'package:flutter/material.dart';

import '../../../components/tags/view/recent_tags_row.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../domain/tags/tag.dart';
import '../../../domain/todo/quick_entry.dart';
import '../new_todo/view/new_todo_sheet.dart';

/// The quick entry at the bottom of a list.
///
/// On the phone docked above the tab bar, on `sf2` with a line above it; on the desktop
/// sticky at the bottom edge of the content column. On a shopping
/// list it understands "2l milch" and turns it into amount, unit and product; anything
/// uncertain lands as plain text.
class QuickEntryBar extends StatefulWidget {
  const QuickEntryBar({
    super.key,
    required this.listId,
    required this.listTags,
    required this.shopping,
    required this.docked,
    required this.onSubmit,
    this.onAdding,
  });

  final String listId;

  /// The list's tags — preselected, so a new task carries them unless they are
  /// deselected.
  final String listTags;
  final bool shopping;
  final bool docked;

  /// A new entry, with the tags picked below it.
  final Future<void> Function(QuickEntry entry, List<String> tags) onSubmit;

  /// A task is on its way from "More fields" — the list follows it into view.
  final VoidCallback? onAdding;

  @override
  State<QuickEntryBar> createState() => _QuickEntryBarState();
}

class _QuickEntryBarState extends State<QuickEntryBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// Stays selected across several entries — whoever notes down five things for "Garten"
  /// types the tag once.
  late final _tags = {...tagIdsOf(widget.listTags)};

  @override
  void didUpdateWidget(QuickEntryBar old) {
    super.didUpdateWidget(old);
    // The list loads after the screen, or its tags change: swap its tags, keep the
    // ones picked here.
    if (old.listTags != widget.listTags) {
      _tags
        ..removeAll(tagIdsOf(old.listTags))
        ..addAll(tagIdsOf(widget.listTags));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final entry = widget.shopping
        ? QuickEntry.parse(text)
        : QuickEntry(title: text);
    _controller.clear();
    // Focus stays: whoever fills a shopping list types several lines in a row.
    _focus.requestFocus();
    await widget.onSubmit(entry, _tags.toList());
  }

  /// Every field of a new task, in a sheet over the list — with what was typed so
  /// far as its title.
  Future<void> _moreFields() async {
    widget.onAdding?.call();
    final created = await showNewTodoSheet(
      context,
      listId: widget.listId,
      title: _controller.text.trim(),
    );
    if (created) _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = context.scheme;

    return Container(
      decoration: widget.docked
          ? BoxDecoration(
              color: scheme.surfaceContainer,
              // The context is BoxBorder: abstract, a shorthand finds no constructor.
              // ignore: many_lints/prefer_shorthands_with_constructors
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            )
          : null,
      padding: widget.docked
          ? EdgeInsets.fromLTRB(
              HiwiskiMetrics.space16,
              HiwiskiMetrics.space10,
              HiwiskiMetrics.space16,
              HiwiskiMetrics.space10 + MediaQuery.viewInsetsOf(context).bottom,
            )
          : const EdgeInsets.only(top: HiwiskiMetrics.space14),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    textInputAction: .send,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: scheme.surface,
                      hintText: widget.shopping
                          ? l.todoNewItemHint
                          : l.todoNewTaskHint,
                      border: const OutlineInputBorder(
                        borderRadius: .all(
                          .circular(HiwiskiMetrics.radiusSearch),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: const .all(
                          .circular(HiwiskiMetrics.radiusSearch),
                        ),
                        borderSide: BorderSide(color: scheme.outline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: const .all(
                          .circular(HiwiskiMetrics.radiusSearch),
                        ),
                        borderSide: BorderSide(
                          width: HiwiskiMetrics.strokeBold,
                          color: scheme.primary,
                        ),
                      ),
                      contentPadding: const .symmetric(
                        horizontal: HiwiskiMetrics.space16,
                        vertical: HiwiskiMetrics.space12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: HiwiskiMetrics.space8),
                if (!widget.shopping)
                  IconButton(
                    icon: const Icon(HiwiskiSymbols.tune),
                    tooltip: l.todoMoreFields,
                    onPressed: _moreFields,
                  ),
                SizedBox.square(
                  dimension: HiwiskiMetrics.iconButtonSize,
                  child: IconButton.filled(
                    // Explicitly `onPrimary`: the theme colours icon buttons `onv`, and on the
                    // filled background the arrow otherwise looked pale, as if disabled.
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                    ),
                    icon: const Icon(HiwiskiSymbols.arrowUpward),
                    onPressed: _submit,
                    tooltip: l.actionAdd,
                  ),
                ),
              ],
            ),
            // Shopping lists group by aisle, not by day — nothing there.
            if (!widget.shopping)
              Padding(
                padding: const .only(top: HiwiskiMetrics.space8),
                child: RecentTagsRow(
                  selected: _tags,
                  onToggle: (id) => setState(
                    () => _tags.contains(id) ? _tags.remove(id) : _tags.add(id),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
