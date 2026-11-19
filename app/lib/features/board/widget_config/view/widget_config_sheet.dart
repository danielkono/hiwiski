import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/color_tokens.dart';
import '../../../../core/ui/list_kind_tile.dart';
import '../../../../core/ui/loading_strip.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../../../core/ui/hiwiski_sheet.dart';
import '../../../../domain/board/board_items.dart';
import '../../../../domain/board/widget_kinds.dart';
import '../../../../domain/todo/kanban.dart';
import '../../view/board_keys.dart';
import '../../widget_tile/view/widget_tile.dart';
import '../widget_config_view_model.dart';

/// "Every kind has **its own configuration page** (sheet on the phone, dialog on
/// the desktop)."
///
/// One shared form with every field would be shorter to write and wrong for every
/// single kind: a clock has no list picker, and a note no
/// look-ahead.
Future<void> showWidgetConfigSheet(
  BuildContext context, {
  required BoardWidget widget,
  bool startBoard = false,
}) {
  return showHiwiskiSheet<void>(
    context: context,
    title: switch (WidgetKind.tryParse(widget.kind)) {
      .calendar => L.of(context).widgetTitleCalendar,
      .calendarWeek => L.of(context).widgetTitleCalendarWeek,
      .todoLists => L.of(context).widgetTitleTodoLists,
      .kanbanBoard => L.of(context).widgetTitleKanban,
      _ => L.of(context).boardConfigure,
    },
    builder: (context) => _ConfigBody(widget: widget, startBoard: startBoard),
  );
}

class _ConfigBody extends ConsumerStatefulWidget {
  const _ConfigBody({required this.widget, required this.startBoard});

  final BoardWidget widget;

  /// On the start board a tile chooses its width here; the wall dashboard sizes its
  /// tiles in its own grid.
  final bool startBoard;

  @override
  ConsumerState<_ConfigBody> createState() => _ConfigBodyState();
}

class _ConfigBodyState extends ConsumerState<_ConfigBody> {
  late WidgetConfig _config = WidgetConfig.decode(widget_.config);

  BoardWidget get widget_ => widget.widget;

  void _set(String key, Object? value) =>
      setState(() => _config = _config.with_(key, value));

  Future<void> _save() async {
    await ref
        .read(widgetConfigViewModelProvider.notifier)
        .configure(widget_, _config);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(widgetConfigViewModelProvider)
      .when(
        skipLoadingOnReload: true,
        loading: () => const LoadingStrip(loading: true),
        error: (error, _) => NoticeBar.failure(context, error: error),
        data: _form,
      );

  Widget _form(WidgetConfigState choices) {
    final l = L.of(context);
    final kind = WidgetKind.tryParse(widget_.kind);

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        // A kind this app does not know cannot be configured either — but it
        // can be shown and removed. The configuration stays
        // **untouched**: an older app must not write away the settings of a newer one.
        if (kind == null)
          Text(l.boardUnknownWidget, style: context.texts.bodyMedium)
        else
          ...switch (kind) {
            .clock => _clock(l),
            .calendar => _calendar(l, choices),
            .calendarWeek => _calendar(l, choices, week: true),
            .todoList || .shoppingList => _list(l, choices),
            .wikiPage => _page(l, choices),
            .note => _note(l),
            .recipe => _recipe(l, choices),
            .todoLists => _lists(l, choices),
            .kanbanBoard => _kanban(l, choices),
            _ => [Text(l.widgetNothingToShow, style: context.texts.bodyMedium)],
          },
        if (kind != null && widget.startBoard) ...[
          const SizedBox(height: HiwiskiMetrics.space16),
          Text(l.boardWidth, style: context.tokens.text.sectionLabel),
          const SizedBox(height: HiwiskiMetrics.space8),
          Wrap(
            spacing: HiwiskiMetrics.space6,
            runSpacing: HiwiskiMetrics.space6,
            children: [
              for (final (width, label) in [
                (StartWidth.normal, l.widgetWidthNormal),
                (StartWidth.wide, l.widgetWidthWide),
                (StartWidth.full, l.widgetWidthFull),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: StartWidth.of(_config, kind) == width,
                  onSelected: (_) =>
                      _set(WidgetConfigKeys.startWidth, width.id),
                ),
            ],
          ),
        ],
        SheetActions(
          children: [FilledButton(onPressed: _save, child: Text(l.actionDone))],
        ),
      ],
    );
  }

  List<Widget> _clock(L l) => [
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _config.boolOr(WidgetConfigKeys.hour24, true),
      title: Text(l.widgetClock24h),
      onChanged: (value) => _set(WidgetConfigKeys.hour24, value),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _config.boolOr(WidgetConfigKeys.seconds, false),
      title: Text(l.widgetClockSeconds),
      onChanged: (value) => _set(WidgetConfigKeys.seconds, value),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _config.boolOr(WidgetConfigKeys.date, true),
      title: Text(l.widgetClockDate),
      onChanged: (value) => _set(WidgetConfigKeys.date, value),
    ),
  ];

  /// Which calendars, and how far ahead — days for the list, days side by side for the
  /// week overview.
  List<Widget> _calendar(L l, WidgetConfigState choices, {bool week = false}) {
    final calendars = choices.calendars;
    // No selection means "all" — that is why all of them then show as checked.
    final stored = _config.ids(WidgetConfigKeys.calendarIds).toSet();
    final chosen = stored.isEmpty
        ? calendars.map((row) => row.id).toSet()
        : stored;
    final days = _config.intOr(WidgetConfigKeys.days, week ? 7 : 3);

    return [
      Text(l.widgetCalendarsShown, style: context.tokens.text.sectionLabel),
      const SizedBox(height: HiwiskiMetrics.space4),
      for (final calendar in calendars)
        _CheckRow(
          checked: chosen.contains(calendar.id),
          color: context.tokens.accent(accentOf(calendar.colorToken)),
          label: calendar.name,
          // The last ticked one stays ticked: an empty selection is "all", and
          // unticking it ticked every calendar again.
          onTap: chosen.length == 1 && chosen.contains(calendar.id)
              ? null
              : () {
                  final next = Set<String>.of(chosen);
                  if (!next.remove(calendar.id)) next.add(calendar.id);
                  _set(WidgetConfigKeys.calendarIds, next.toList());
                },
        ),
      const SizedBox(height: HiwiskiMetrics.space16),
      Text(
        week ? l.widgetWeekDays : l.widgetCalendarRange,
        style: context.tokens.text.sectionLabel,
      ),
      const SizedBox(height: HiwiskiMetrics.space8),
      Wrap(
        spacing: HiwiskiMetrics.space6,
        runSpacing: HiwiskiMetrics.space6,
        children: [
          for (final value in week ? const [3, 5, 7] : const [1, 2, 3, 7, 14])
            FilterChip(
              label: Text(
                week ? l.widgetWeekDaysCount(value) : rangeLabel(l, value),
              ),
              selected: days == value,
              onSelected: (_) => _set(WidgetConfigKeys.days, value),
            ),
        ],
      ),
      if (week)
        const SizedBox(height: HiwiskiMetrics.space8)
      else ...[
        const SizedBox(height: HiwiskiMetrics.space8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(HiwiskiSymbols.schedule),
          value: _config.boolOr(WidgetConfigKeys.hidePast, false),
          title: Text(l.widgetCalendarHidePast),
          onChanged: (value) => _set(WidgetConfigKeys.hidePast, value),
        ),
      ],
    ];
  }

  List<Widget> _lists(L l, WidgetConfigState choices) {
    final all = choices.lists;
    final chosen = selectedLists(
      _config,
      all,
    ).map((summary) => summary.list.id).toSet();
    return [
      Text(l.widgetListsShown, style: context.tokens.text.sectionLabel),
      const SizedBox(height: HiwiskiMetrics.space4),
      for (final summary in all)
        _CheckRow(
          checked: chosen.contains(summary.list.id),
          color: chosen.contains(summary.list.id)
              ? context.scheme.primary
              : context.scheme.onSurfaceVariant,
          label: summary.list.name,
          icon: listKindIcon(summary.list.kind),
          onTap: () {
            final next = Set<String>.of(chosen);
            if (!next.remove(summary.list.id)) next.add(summary.list.id);
            _set(WidgetConfigKeys.listIds, next.toList());
          },
        ),
      const SizedBox(height: HiwiskiMetrics.space8),
      Text(
        l.widgetListsHint,
        style: context.texts.bodySmall?.copyWith(
          color: context.scheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  /// Which board, and whether whole or one column — then which, and how many cards.
  List<Widget> _kanban(L l, WidgetConfigState choices) {
    final boards = choices.boards;
    final listId = _config.get<String>(WidgetConfigKeys.listId);
    final board = boards.where((s) => s.list.id == listId).firstOrNull?.list;
    final columns = parseColumns(board?.columns);
    final oneColumn = kanbanOneColumn(_config);
    if (boards.isEmpty) {
      return [Text(l.widgetKanbanNone, style: context.texts.bodyMedium)];
    }
    return [
      DropdownButtonFormField<String>(
        key: BoardKeys.widgetKanbanBoard,
        initialValue: board?.id,
        decoration: InputDecoration(labelText: l.widgetKanbanWhich),
        items: [
          for (final summary in boards)
            DropdownMenuItem(
              value: summary.list.id,
              child: Text(summary.list.name),
            ),
        ],
        onChanged: (value) => setState(
          () => _config = _config
              .with_(WidgetConfigKeys.listId, value)
              .with_(WidgetConfigKeys.columnId, null),
        ),
      ),
      const SizedBox(height: HiwiskiMetrics.space16),
      Wrap(
        spacing: HiwiskiMetrics.space6,
        children: [
          ChoiceChip(
            label: Text(l.widgetKanbanWhole),
            selected: !oneColumn,
            onSelected: (_) =>
                _set(WidgetConfigKeys.mode, KanbanTileModes.board),
          ),
          ChoiceChip(
            key: BoardKeys.widgetKanbanOneColumn,
            label: Text(l.widgetKanbanOneColumn),
            selected: oneColumn,
            onSelected: (_) =>
                _set(WidgetConfigKeys.mode, KanbanTileModes.column),
          ),
        ],
      ),
      if (oneColumn && columns.isNotEmpty) ...[
        const SizedBox(height: HiwiskiMetrics.space16),
        DropdownButtonFormField<String>(
          key: BoardKeys.widgetKanbanColumn,
          initialValue: columns
              .where(
                (c) => c.id == _config.get<String>(WidgetConfigKeys.columnId),
              )
              .firstOrNull
              ?.id,
          decoration: InputDecoration(labelText: l.widgetKanbanWhichColumn),
          items: [
            for (final column in columns)
              DropdownMenuItem(value: column.id, child: Text(column.name)),
          ],
          onChanged: (value) => _set(WidgetConfigKeys.columnId, value),
        ),
        const SizedBox(height: HiwiskiMetrics.space8),
        Row(
          children: [
            Text(l.widgetCount),
            const Spacer(),
            for (final count in const [3, 6, 10])
              Padding(
                padding: const .only(left: HiwiskiMetrics.space8),
                child: ChoiceChip(
                  label: Text('$count'),
                  selected: _config.intOr(WidgetConfigKeys.count, 6) == count,
                  onSelected: (_) => _set(WidgetConfigKeys.count, count),
                ),
              ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _list(L l, WidgetConfigState choices) {
    final shopping = widget_.kind == WidgetKind.shoppingList.id;
    final lists = shopping ? choices.shoppingLists : choices.lists;

    return [
      DropdownButtonFormField<String>(
        initialValue: _config.get<String>(WidgetConfigKeys.listId),
        decoration: InputDecoration(labelText: l.widgetListWhich),
        items: [
          for (final summary in lists)
            DropdownMenuItem(
              value: summary.list.id,
              child: Text(summary.list.name),
            ),
        ],
        onChanged: (value) => _set(WidgetConfigKeys.listId, value),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _config.boolOr(WidgetConfigKeys.showDone, false),
        title: Text(l.widgetShowDone),
        onChanged: (value) => _set(WidgetConfigKeys.showDone, value),
      ),
      if (!shopping)
        Row(
          children: [
            Text(l.widgetCount),
            const Spacer(),
            for (final count in const [3, 6, 10])
              Padding(
                padding: const .only(left: HiwiskiMetrics.space8),
                child: ChoiceChip(
                  label: Text('$count'),
                  selected: _config.intOr(WidgetConfigKeys.count, 6) == count,
                  onSelected: (_) => _set(WidgetConfigKeys.count, count),
                ),
              ),
          ],
        ),
    ];
  }

  List<Widget> _page(L l, WidgetConfigState choices) {
    final pages = choices.plainPages;
    return [
      DropdownButtonFormField<String>(
        initialValue: _config.get<String>(WidgetConfigKeys.pageId),
        decoration: InputDecoration(labelText: l.widgetPageWhich),
        items: [
          for (final page in pages)
            DropdownMenuItem(value: page.id, child: Text(page.title)),
        ],
        onChanged: (value) => _set(WidgetConfigKeys.pageId, value),
      ),
    ];
  }

  List<Widget> _recipe(L l, WidgetConfigState choices) {
    final recipes = choices.recipes;
    return [
      DropdownButtonFormField<String?>(
        initialValue: _config.get<String>(WidgetConfigKeys.recipeId),
        decoration: InputDecoration(labelText: l.widgetRecipe),
        items: [
          DropdownMenuItem(value: null, child: Text(l.widgetRecipeOfTheDay)),
          for (final recipe in recipes)
            DropdownMenuItem(value: recipe.id, child: Text(recipe.title)),
        ],
        onChanged: (value) => _set(WidgetConfigKeys.recipeId, value),
      ),
    ];
  }

  List<Widget> _note(L l) => [
    TextFormField(
      key: BoardKeys.widgetNoteText,
      initialValue: _config.get<String>(WidgetConfigKeys.text) ?? '',
      decoration: InputDecoration(labelText: l.widgetNoteText),
      maxLines: 5,
      minLines: 2,
      onChanged: (value) => _set(WidgetConfigKeys.text, value),
    ),
  ];
}

/// A row with a checkbox: in the calendar's colour or `pri`, `FILL 1` when on.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.checked,
    required this.color,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final bool checked;
  final Color color;
  final String label;

  /// `null`: shown, but it cannot be changed.
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: HiwiskiMetrics.minTapTarget),
      child: Row(
        children: [
          Icon(
            checked
                ? HiwiskiSymbols.checkBox
                : HiwiskiSymbols.checkBoxOutlineBlank,
            fill: checked ? 1 : 0,
            color: color,
          ),
          const SizedBox(width: HiwiskiMetrics.space12),
          if (icon != null) ...[
            Icon(
              icon,
              size: HiwiskiMetrics.icon20,
              color: context.scheme.onSurfaceVariant,
            ),
            const SizedBox(width: HiwiskiMetrics.space12),
          ],
          Expanded(child: Text(label, style: context.texts.bodyLarge)),
        ],
      ),
    ),
  );
}
