import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/common/wire.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/hiwiski_sheet.dart';
import '../../../core/ui/color_tokens.dart';
import '../../../domain/todo/kanban.dart';
import 'todo_keys.dart';
import '../../../domain/todo/todo_items.dart';
import '../../../core/ui/color_picker.dart';

/// "To do / Doing / Done" — what a new board starts with.
List<KanbanColumn> defaultKanbanColumns(L l) => [
  KanbanColumn.create(l.kanbanDefaultTodo, colorToken: ColorTokens.blue),
  KanbanColumn.create(l.kanbanDefaultDoing, colorToken: ColorTokens.ochre),
  KanbanColumn.create(
    l.kanbanDefaultDone,
    colorToken: ColorTokens.green,
    done: true,
  ),
];

/// The columns of a board as rows: drag handle, color dot, name, the done mark, remove.
///
/// "Add column" is gone at 8, a row's remove button at 2. A row's done mark turns it
/// into a done column and back — any number of them, but at least one is done and one
/// stays open.
class KanbanColumnsEditor extends StatefulWidget {
  const KanbanColumnsEditor({
    super.key,
    required this.columns,
    required this.onChanged,
  });

  final List<KanbanColumn> columns;
  final ValueChanged<List<KanbanColumn>> onChanged;

  @override
  State<KanbanColumnsEditor> createState() => _KanbanColumnsEditorState();
}

class _KanbanColumnsEditorState extends State<KanbanColumnsEditor> {
  /// One field per column, by id — so typing in a row survives reordering it.
  final _names = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final controller in _names.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _nameOf(KanbanColumn column) => _names.putIfAbsent(
    column.id,
    () => TextEditingController(text: column.name),
  );

  List<KanbanColumn> get _columns => widget.columns;

  void _replace(int index, KanbanColumn column) =>
      widget.onChanged([..._columns]..[index] = column);

  /// Whether the mark of the column at [index] may be switched: not on the last done
  /// column, nor on the last open one.
  bool _switchable(int index) {
    final done = _columns[index].done;
    return _columns.where((column) => column.done == done).length > 1;
  }

  void _toggleDone(int index) =>
      _replace(index, _columns[index].copyWith(done: !_columns[index].done));

  void _remove(int index) {
    final removed = _columns[index];
    final next = [..._columns]..removeAt(index);
    // The mark of the last done column stays on the board, with the column now last.
    // And when the last open column goes, the first column is open from then on.
    if (!next.any((column) => column.done)) {
      next[next.length - 1] = next.last.copyWith(done: true);
    }
    if (!next.any((column) => !column.done)) {
      next[0] = next.first.copyWith(done: false);
    }
    _names.remove(removed.id)?.dispose();
    widget.onChanged(next);
  }

  void _add(L l) {
    // New columns go before the first done column — those stay at the end, where
    // cards finish.
    final doneAt = _columns.indexWhere((column) => column.done);
    final used = _columns.map((column) => column.colorToken).toSet();
    final color = calendarColorTokens.firstWhere(
      (token) => !used.contains(token),
      orElse: () => ColorTokens.slate,
    );
    final column = KanbanColumn.create(l.kanbanNewColumn, colorToken: color);
    final next = [..._columns];
    next.insert(doneAt < 0 ? next.length : doneAt, column);
    widget.onChanged(next);
  }

  Future<void> _pickColor(int index) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.of(context).kanbanColumnColor),
        content: ColorPicker(
          selected: _columns[index].colorToken,
          onSelected: (token) => Navigator.of(context).pop(token),
        ),
      ),
    );
    if (picked != null && mounted) {
      _replace(index, _columns[index].copyWith(colorToken: picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = context.scheme;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Text(l.kanbanColumns, style: context.tokens.text.sectionLabel),
        const SizedBox(height: HiwiskiMetrics.space4),
        Text(
          l.kanbanColumnsHint,
          style: context.texts.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space8),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) {
            final next = [..._columns];
            next.insert(to, next.removeAt(from));
            widget.onChanged(next);
          },
          children: [
            for (final (index, column) in _columns.indexed)
              Padding(
                key: TodoKeys.kanbanColumn(column.id),
                padding: const .symmetric(vertical: HiwiskiMetrics.space4),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        padding: const .all(HiwiskiMetrics.space4),
                        child: Icon(
                          HiwiskiSymbols.dragIndicator,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l.kanbanColumnColor,
                      onPressed: () => _pickColor(index),
                      icon: Container(
                        width: HiwiskiMetrics.icon22,
                        height: HiwiskiMetrics.icon22,
                        decoration: BoxDecoration(
                          color: context.tokens.accent(
                            accentOf(column.colorToken),
                          ),
                          shape: .circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        key: TodoKeys.kanbanColumnName(column.id),
                        controller: _nameOf(column),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: l.kanbanColumnName,
                        ),
                        onChanged: (name) => _replace(
                          _columns.indexWhere((c) => c.id == column.id),
                          column.copyWith(name: name),
                        ),
                      ),
                    ),
                    IconButton(
                      key: TodoKeys.kanbanColumnDone(column.id),
                      tooltip: switch ((column.done, _switchable(index))) {
                        (true, true) => l.kanbanMakeOpen,
                        (true, false) => l.kanbanDoneColumn,
                        (false, _) => l.kanbanMakeDone,
                      },
                      onPressed: _switchable(index)
                          ? () => _toggleDone(index)
                          : null,
                      icon: Icon(
                        HiwiskiSymbols.checkCircle,
                        fill: column.done ? 1 : 0,
                        color: column.done
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    if (_columns.length > kanbanMinColumns)
                      IconButton(
                        tooltip: l.kanbanRemoveColumn,
                        onPressed: () => _remove(index),
                        icon: const Icon(HiwiskiSymbols.close),
                      )
                    else
                      const SizedBox(width: HiwiskiMetrics.iconButtonSize),
                  ],
                ),
              ),
          ],
        ),
        if (_columns.length < kanbanMaxColumns)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: TodoKeys.kanbanAddColumn,
              onPressed: () => _add(l),
              icon: const Icon(HiwiskiSymbols.add),
              label: Text(l.kanbanAddColumn),
            ),
          ),
      ],
    );
  }
}

/// "Edit columns" on a board. Removing a column that still holds cards asks first and
/// says where they go.
Future<void> showEditColumnsSheet(
  BuildContext context, {
  required TodoList list,
  required List<Todo> cards,
  required Future<void> Function(List<KanbanColumn> columns) onSave,
}) async {
  final l = L.of(context);
  final before = parseColumns(list.columns);
  final edited = await showHiwiskiSheet<List<KanbanColumn>>(
    context: context,
    title: l.kanbanEditColumns,
    builder: (context) => _ColumnsBody(initial: before, action: l.actionSave),
  );
  if (edited == null || !context.mounted) return;

  final moves = planColumnChange(
    before,
    edited,
    cards,
  ).where((change) => change.from != change.to).toList();
  if (moves.isNotEmpty) {
    String nameOf(String id) =>
        [...before, ...edited].firstWhere((column) => column.id == id).name;
    final counts = <(String, String), int>{};
    for (final move in moves) {
      counts.update((move.from, move.to), (n) => n + 1, ifAbsent: () => 1);
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.kanbanRemoveTitle),
        content: Text(
          [
            for (final MapEntry(key: (from, to), value: count)
                in counts.entries)
              l.kanbanMoveCards(count, nameOf(from), nameOf(to)),
          ].join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.actionSave),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
  }
  await onSave(edited);
}

/// "Convert to board" on a task list: the columns, and what will happen to the tasks.
Future<void> showConvertToKanbanSheet(
  BuildContext context, {
  required List<Todo> cards,
  required Future<void> Function(List<KanbanColumn> columns) onConvert,
}) async {
  final l = L.of(context);
  final repeating = cards.where((card) => (card.rrule ?? '').isNotEmpty).length;
  final columns = await showHiwiskiSheet<List<KanbanColumn>>(
    context: context,
    title: l.kanbanConvertTitle,
    builder: (context) => _ColumnsBody(
      initial: defaultKanbanColumns(l),
      action: l.kanbanConvertAction,
      notes: [
        l.kanbanConvertBody,
        if (repeating > 0) l.kanbanConvertRepeats(repeating),
      ],
    ),
  );
  if (columns == null) return;
  await onConvert(columns);
}

class _ColumnsBody extends StatefulWidget {
  const _ColumnsBody({
    required this.initial,
    required this.action,
    this.notes = const [],
  });

  final List<KanbanColumn> initial;
  final String action;
  final List<String> notes;

  @override
  State<_ColumnsBody> createState() => _ColumnsBodyState();
}

class _ColumnsBodyState extends State<_ColumnsBody> {
  late var _columns = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final cleaned = [
      for (final column in _columns) column.copyWith(name: column.name.trim()),
    ];
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        for (final note in widget.notes) ...[
          Text(note, style: context.texts.bodyMedium),
          const SizedBox(height: HiwiskiMetrics.space12),
        ],
        KanbanColumnsEditor(
          columns: _columns,
          onChanged: (next) => setState(() => _columns = next),
        ),
        SheetActions(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.actionCancel),
            ),
            FilledButton(
              key: TodoKeys.kanbanColumnsSave,
              onPressed: columnsValid(cleaned)
                  ? () => Navigator.of(context).pop(cleaned)
                  : null,
              child: Text(widget.action),
            ),
          ],
        ),
      ],
    );
  }
}
