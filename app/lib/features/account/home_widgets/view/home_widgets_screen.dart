import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/shell/breakpoints.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/color_tokens.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../../../core/ui/hiwiski_sheet.dart';
import '../../../../core/ui/list_kind_tile.dart';
import '../../../../core/ui/page_header.dart';
import '../../../../core/common/wire.dart';
import '../../../../domain/home_widgets/home_widget_settings.dart';
import '../../../../domain/todo/kanban.dart';
import '../../../../domain/todo/todo_models.dart';
import '../../view/account_keys.dart';
import '../../view/account_row.dart';
import '../home_widgets_view_model.dart';

/// Account → Widgets: what each home screen widget of this device shows.
///
/// The widgets themselves are added on the home screen, as every app's are; here they
/// get their content. A widget not set up yet leads here when tapped, with its
/// settings open ([open]).
class HomeWidgetsScreen extends ConsumerStatefulWidget {
  const HomeWidgetsScreen({super.key, this.open});

  /// The widget whose settings open at once.
  final HomeWidgetKind? open;

  @override
  ConsumerState<HomeWidgetsScreen> createState() => _HomeWidgetsScreenState();
}

class _HomeWidgetsScreenState extends ConsumerState<HomeWidgetsScreen> {
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    // Once, as soon as there is something to choose from.
    ref.listenManual(homeWidgetsViewModelProvider, (_, next) {
      final kind = widget.open;
      final state = next.value;
      if (_opened || kind == null || state == null) return;
      _opened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _configure(kind, state);
      });
    }, fireImmediately: true);
  }

  void _configure(HomeWidgetKind kind, HomeWidgetsState state) {
    final sheet = showHiwiskiSheet<void>(
      context: context,
      title: kindTitle(L.of(context), kind),
      builder: (context) => _ConfigForm(kind: kind, state: state),
    );
    // The sheet saves through its own form; closing it answers nothing to wait for.
    sheet.ignore();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final padding = Breakpoint.of(context).pagePadding;
    final header = PageHeader(
      title: l.homeWidgetsTitle,
      onBack: () => const AccountRoute().go(context),
    );
    return ref
        .watch(homeWidgetsViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(header: header, error: error),
          data: (state) => HiwiskiPage(
            header: header,
            body: ListView(
              padding: padding,
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: HiwiskiMetrics.listMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        Text(
                          l.homeWidgetsHint,
                          style: context.texts.bodyMedium?.copyWith(
                            color: context.scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: HiwiskiMetrics.space16),
                        for (final kind in HomeWidgetKind.values)
                          AccountRow(
                            key: AccountKeys.homeWidgetRow(kind.name),
                            icon: kindIcon(kind),
                            label: kindTitle(l, kind),
                            subtitle: _summary(l, kind, state.summaries[kind]),
                            onTap: () => _configure(kind, state),
                          ),
                        const SizedBox(height: HiwiskiMetrics.space16),
                        Text(
                          l.homeWidgetsRefreshHint,
                          style: context.texts.bodySmall?.copyWith(
                            color: context.scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
  }

  String _summary(L l, HomeWidgetKind kind, HomeWidgetSummary? summary) {
    final config = summary?.config;
    if (summary == null || config == null) return l.homeWidgetNotSetUp;
    if (summary.missing) return l.homeWidgetMissing;
    return switch (kind) {
      .agenda => [
        if (summary.names.isEmpty)
          l.homeWidgetAllCalendars
        else
          summary.names.join(', '),
        rangeName(l, config.days),
      ].join(' · '),
      .kanban => [...summary.names, ?summary.column].join(' · '),
      .shopping || .tasks => summary.names.join(', '),
    };
  }
}

String kindTitle(L l, HomeWidgetKind kind) => switch (kind) {
  .agenda => l.homeWidgetAgenda,
  .shopping => l.homeWidgetShopping,
  .tasks => l.homeWidgetTasks,
  .kanban => l.homeWidgetKanban,
};

IconData kindIcon(HomeWidgetKind kind) => switch (kind) {
  .agenda => HiwiskiSymbols.calendarMonth,
  .shopping => listKindIcon(ListKinds.shopping),
  .tasks => listKindIcon(ListKinds.standard),
  .kanban => listKindIcon(ListKinds.kanban),
};

/// The look-ahead as the start board's calendar tile names it.
String rangeName(L l, int days) => switch (days) {
  1 => l.widgetRangeToday,
  2 => l.widgetRangeTomorrow,
  7 => l.widgetRange7,
  14 => l.widgetRange14,
  _ => l.widgetRange3,
};

/// The settings of one widget: one form per kind, as on the start board.
class _ConfigForm extends ConsumerStatefulWidget {
  const _ConfigForm({required this.kind, required this.state});

  final HomeWidgetKind kind;
  final HomeWidgetsState state;

  @override
  ConsumerState<_ConfigForm> createState() => _ConfigFormState();
}

class _ConfigFormState extends ConsumerState<_ConfigForm> {
  late HomeWidgetConfig _config =
      widget.state.summaries[widget.kind]?.config ?? const HomeWidgetConfig();

  HomeWidgetKind get _kind => widget.kind;

  bool get _configured => widget.state.summaries[_kind]?.config != null;

  Future<void> _save(HomeWidgetConfig? config) async {
    await ref
        .read(homeWidgetsViewModelProvider.notifier)
        .configure(_kind, config);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        ...switch (_kind) {
          .agenda => _agenda(l),
          .shopping => _list(l, widget.state.shoppingLists),
          .tasks => _list(l, widget.state.taskLists),
          .kanban => _kanban(l),
        },
        SheetActions(
          children: [
            if (_configured)
              TextButton(
                key: AccountKeys.homeWidgetRemove,
                onPressed: () => _save(null),
                child: Text(l.homeWidgetRemove),
              ),
            FilledButton(
              key: AccountKeys.homeWidgetDone,
              onPressed: _config.completeFor(_kind)
                  ? () => _save(_config)
                  : null,
              child: Text(l.actionDone),
            ),
          ],
        ),
      ],
    );
  }

  /// Which calendars, and how far ahead. No choice means all of them — they then all
  /// show as ticked, and the last one ticked stays ticked.
  List<Widget> _agenda(L l) {
    final calendars = widget.state.calendars;
    final stored = _config.calendarIds.toSet();
    final chosen = stored.isEmpty
        ? calendars.map((calendar) => calendar.id).toSet()
        : stored;
    return [
      Text(l.widgetCalendarsShown, style: context.tokens.text.sectionLabel),
      const SizedBox(height: HiwiskiMetrics.space4),
      for (final calendar in calendars)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: .leading,
          activeColor: context.tokens.accent(accentOf(calendar.colorToken)),
          value: chosen.contains(calendar.id),
          title: Text(calendar.name),
          onChanged: chosen.length == 1 && chosen.contains(calendar.id)
              ? null
              : (_) {
                  final next = Set<String>.of(chosen);
                  if (!next.remove(calendar.id)) next.add(calendar.id);
                  setState(
                    () => _config = HomeWidgetConfig(
                      // Every calendar ticked is "all" — new ones come along.
                      calendarIds: next.length == calendars.length
                          ? const []
                          : next.toList(),
                      days: _config.days,
                    ),
                  );
                },
        ),
      const SizedBox(height: HiwiskiMetrics.space16),
      Text(l.widgetCalendarRange, style: context.tokens.text.sectionLabel),
      const SizedBox(height: HiwiskiMetrics.space8),
      Wrap(
        spacing: HiwiskiMetrics.space6,
        runSpacing: HiwiskiMetrics.space6,
        children: [
          for (final days in HomeWidgetConfig.dayChoices)
            FilterChip(
              label: Text(rangeName(l, days)),
              selected: _config.days == days,
              onSelected: (_) => setState(
                () => _config = HomeWidgetConfig(
                  calendarIds: _config.calendarIds,
                  days: days,
                ),
              ),
            ),
        ],
      ),
    ];
  }

  List<Widget> _list(L l, List<TodoListSummary> lists) {
    if (lists.isEmpty) {
      return [Text(l.homeWidgetNoList, style: context.texts.bodyMedium)];
    }
    return [
      DropdownButtonFormField<String>(
        key: AccountKeys.homeWidgetList,
        initialValue: lists
            .where((summary) => summary.list.id == _config.listId)
            .firstOrNull
            ?.list
            .id,
        decoration: InputDecoration(labelText: l.widgetListWhich),
        items: [
          for (final summary in lists)
            DropdownMenuItem(
              value: summary.list.id,
              child: Text(summary.list.name),
            ),
        ],
        onChanged: (value) =>
            setState(() => _config = HomeWidgetConfig(listId: value)),
      ),
    ];
  }

  List<Widget> _kanban(L l) {
    final boards = widget.state.boards;
    if (boards.isEmpty) {
      return [Text(l.widgetKanbanNone, style: context.texts.bodyMedium)];
    }
    final board = boards
        .where((summary) => summary.list.id == _config.listId)
        .firstOrNull
        ?.list;
    final columns = parseColumns(board?.columns);
    return [
      DropdownButtonFormField<String>(
        key: AccountKeys.homeWidgetList,
        initialValue: board?.id,
        decoration: InputDecoration(labelText: l.widgetKanbanWhich),
        items: [
          for (final summary in boards)
            DropdownMenuItem(
              value: summary.list.id,
              child: Text(summary.list.name),
            ),
        ],
        // Another board has other columns.
        onChanged: (value) =>
            setState(() => _config = HomeWidgetConfig(listId: value)),
      ),
      if (columns.isNotEmpty) ...[
        const SizedBox(height: HiwiskiMetrics.space16),
        DropdownButtonFormField<String>(
          key: AccountKeys.homeWidgetColumn,
          initialValue: columns
              .where((column) => column.id == _config.columnId)
              .firstOrNull
              ?.id,
          decoration: InputDecoration(labelText: l.widgetKanbanWhichColumn),
          items: [
            for (final column in columns)
              DropdownMenuItem(value: column.id, child: Text(column.name)),
          ],
          onChanged: (value) => setState(
            () => _config = HomeWidgetConfig(
              listId: _config.listId,
              columnId: value,
            ),
          ),
        ),
      ],
    ];
  }
}
