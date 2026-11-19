import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../components/assignees/view/assignees.dart';
import '../../../../components/rich_text/view/rich_text_editor.dart';
import '../../../../components/rich_text/view/markdown_text_controller.dart';
import '../../../../components/sharing/view/share_draft_section.dart';
import '../../../../components/tags/view/tag_field.dart';
import '../../../../core/api/generated/export.dart' hide Mutation;
import '../../../../core/common/wire.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/hiwiski_sheet.dart';
import '../../../../domain/todo/kanban.dart';
import '../../view/kanban_columns_editor.dart';
import '../../view/todo_keys.dart';
import '../new_list_view_model.dart';

/// "New list" — sheet on the phone, dialog on the desktop, one component.
///
/// The **kind** sits at the top as three large selection tiles and
/// cannot be changed after creation: a shopping list has amounts and aisles, a
/// task list has due dates. That is why it is decided here and nowhere
/// else — the one exception being a task list that later becomes a board.
///
/// Choosing Kanban adds the board's columns below the kind.
Future<String?> showNewListSheet(BuildContext context) {
  return showHiwiskiSheet<String>(
    context: context,
    title: L.of(context).todoNewList,
    builder: (context) => const _NewListBody(),
  );
}

class _NewListBody extends ConsumerStatefulWidget {
  const _NewListBody();

  @override
  ConsumerState<_NewListBody> createState() => _NewListBodyState();
}

class _NewListBodyState extends ConsumerState<_NewListBody> {
  final _name = TextEditingController();
  final _description = MarkdownTextController();
  final _descriptionFocus = FocusNode();
  String _kind = ListKinds.standard;
  final _assignees = <String>{};
  Set<String> _tags = {};
  List<WriteShare> _shares = [];

  /// The board's columns — filled the first time Kanban is chosen.
  List<KanbanColumn>? _columns;

  bool get _kanban => _kind == kindKanban;

  List<KanbanColumn> get _cleanColumns => [
    for (final column in _columns ?? const <KanbanColumn>[])
      column.copyWith(name: column.name.trim()),
  ];

  bool get _ready =>
      _name.text.trim().isNotEmpty && (!_kanban || columnsValid(_cleanColumns));

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (!_ready) return;
    final id = await createListMutation.run(
      ref,
      (tsx) => tsx
          .get(newListViewModelProvider.notifier)
          .create(
            name: name,
            kind: _kind,
            description: _description.text.trim().isEmpty
                ? null
                : _description.text.trim(),
            assignees: _assignees.toList(),
            tags: _tags.toList(),
            columns: _kanban ? _cleanColumns : null,
            shares: _shares,
          ),
    );
    if (mounted) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _KindTile(
                icon: HiwiskiSymbols.checklist,
                title: l.todoKindStandard,
                hint: l.todoKindStandardHint,
                selected: _kind == ListKinds.standard,
                onTap: () => setState(() => _kind = ListKinds.standard),
              ),
            ),
            const SizedBox(width: HiwiskiMetrics.space12),
            Expanded(
              child: _KindTile(
                icon: HiwiskiSymbols.shoppingCart,
                title: l.todoKindShopping,
                hint: l.todoKindShoppingHint,
                selected: _kind == ListKinds.shopping,
                onTap: () => setState(() => _kind = ListKinds.shopping),
              ),
            ),
            const SizedBox(width: HiwiskiMetrics.space12),
            Expanded(
              child: _KindTile(
                key: TodoKeys.kindKanban,
                icon: HiwiskiSymbols.viewKanban,
                title: l.todoKindKanban,
                hint: l.todoKindKanbanHint,
                selected: _kanban,
                onTap: () => setState(() {
                  _kind = kindKanban;
                  _columns ??= defaultKanbanColumns(l);
                }),
              ),
            ),
          ],
        ),
        if (_columns case final columns? when _kanban) ...[
          const SizedBox(height: HiwiskiMetrics.space20),
          KanbanColumnsEditor(
            columns: columns,
            onChanged: (next) => setState(() => _columns = next),
          ),
        ],
        const SizedBox(height: HiwiskiMetrics.space20),
        TextField(
          controller: _name,
          autofocus: true,
          textInputAction: .done,
          onSubmitted: (_) => _create(),
          decoration: InputDecoration(labelText: l.todoListName),
        ),
        const SizedBox(height: HiwiskiMetrics.space12),
        // Written like a wiki page, as when the list is edited later: the insert
        // bar, `#` suggesting items. Images once the list exists — there is
        // nothing to hang them on yet.
        RichTextEditor(
          controller: _description,
          focusNode: _descriptionFocus,
          fieldKey: TodoKeys.listDescription,
          label: l.listDescription,
          hint: l.linkHintDescription,
          minLines: 2,
        ),
        const SizedBox(height: HiwiskiMetrics.space20),
        TagField(
          selected: _tags,
          onChanged: (next) => setState(() => _tags = next),
        ),
        const SizedBox(height: HiwiskiMetrics.space20),
        AssigneeChips(
          selected: _assignees,
          hint: l.listAssignedHint,
          onToggle: (id) => setState(
            () => _assignees.contains(id)
                ? _assignees.remove(id)
                : _assignees.add(id),
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space16),
        ShareDraftSection(
          itemType: EntityTypes.todoList,
          shares: _shares,
          onChanged: (next) => setState(() => _shares = next),
        ),
        SheetActions(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.actionCancel),
            ),
            // Follows the name field: a list needs one.
            ListenableBuilder(
              listenable: _name,
              builder: (context, _) => FilledButton(
                onPressed: _ready ? _create : null,
                child: Text(l.tagCreate),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KindTile extends StatelessWidget {
  const _KindTile({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return InkWell(
      onTap: onTap,
      borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
      child: Container(
        padding: const .all(HiwiskiMetrics.space14),
        decoration: BoxDecoration(
          color: selected
              ? scheme.secondaryContainer
              : scheme.surfaceContainerLow,
          borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
          border: .fromBorderSide(
            BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected
                  ? HiwiskiMetrics.strokeBold
                  : HiwiskiMetrics.hairline,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Icon(
              icon,
              // FILL 1 for selected -- the only state indicator on an icon.
              fill: selected ? 1 : 0,
              color: selected
                  ? scheme.onSecondaryContainer
                  : scheme.onSurfaceVariant,
            ),
            const SizedBox(height: HiwiskiMetrics.space8),
            Text(title, style: context.texts.titleSmall),
            Text(
              hint,
              style: context.texts.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
