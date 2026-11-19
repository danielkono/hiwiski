import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/shell/breakpoints.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/dashed_border.dart';
import '../../../../core/ui/page_header.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../../../domain/board/board_items.dart';
import '../../../../domain/board/widget_kinds.dart';
import '../../view/board_grid.dart';
import '../../widget_config/view/widget_config_sheet.dart';
import '../../widget_tile/view/widget_summary.dart';
import '../../widget_tile/view/widget_tile.dart';
import '../start_view_model.dart';

/// The start board.
///
/// **Widget grid, minimum width 320, spacing 14. The tiles have different heights —
/// this is the one place where a `GridView` is not enough.** Hence `flutter_staggered_grid_view`, a deliberate dependency.
class StartScreen extends ConsumerStatefulWidget {
  const StartScreen({super.key});

  @override
  ConsumerState<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends ConsumerState<StartScreen> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final date = DateFormat.yMMMMEEEEd(locale).format(clock.now());
    final header = PageHeader(title: '', kicker: date);
    return ref
        .watch(startViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(header: header, error: error),
          data: (state) {
            final l = L.of(context);
            final padding = Breakpoint.of(context).pagePadding;

            return HiwiskiPage(
              header: PageHeader(title: _greeting(l, state.name), kicker: date),
              filter: CustomPageFilter(
                hint: l.pullToCustomize,
                forceShown: _editing,
                bar: Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    _Toolbar(
                      editing: _editing,
                      onToggle: () => setState(() => _editing = !_editing),
                      onAdd: (kind) => ref
                          .read(startViewModelProvider.notifier)
                          .addWidget(kind),
                    ),
                    if (_editing)
                      Padding(
                        padding: const .only(top: HiwiskiMetrics.space12),
                        child: Text(
                          l.boardEditHint,
                          style: context.texts.bodySmall?.copyWith(
                            color: context.scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              body: _Tiles(
                widgets: state.widgets,
                editing: _editing,
                padding: padding,
                onAdd: (kind) =>
                    ref.read(startViewModelProvider.notifier).addWidget(kind),
              ),
            );
          },
        );
  }

  /// "Good morning, Anna" — depending on the time of day.
  static String _greeting(L l, String name) {
    final hour = clock.now().hour;
    if (hour < 11) return l.homeGreetingMorning(name);
    if (hour < 18) return l.homeGreetingDay(name);
    return l.homeGreetingEvening(name);
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.editing,
    required this.onToggle,
    required this.onAdd,
  });

  final bool editing;
  final VoidCallback onToggle;
  final ValueChanged<WidgetKind> onAdd;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Wrap(
      alignment: .end,
      spacing: HiwiskiMetrics.space8,
      runSpacing: HiwiskiMetrics.space8,
      children: [
        // In edit mode, "+ Calendar" and "+ Tasks" appear on the left.
        if (editing)
          for (final kind in WidgetKind.forStartBoard)
            OutlinedButton.icon(
              icon: const Icon(HiwiskiSymbols.add, size: HiwiskiMetrics.icon18),
              label: Text(widgetKindLabel(l, kind)),
              onPressed: () => onAdd(kind),
            ),
        if (editing)
          FilledButton.icon(
            icon: const Icon(HiwiskiSymbols.check, size: HiwiskiMetrics.icon18),
            label: Text(l.boardDone),
            onPressed: onToggle,
          )
        else
          OutlinedButton.icon(
            icon: const Icon(HiwiskiSymbols.tune, size: HiwiskiMetrics.icon18),
            label: Text(l.boardCustomize),
            onPressed: onToggle,
          ),
      ],
    );
  }
}

class _Tiles extends ConsumerWidget {
  const _Tiles({
    required this.widgets,
    required this.editing,
    required this.padding,
    required this.onAdd,
  });

  final List<BoardWidget> widgets;
  final bool editing;
  final EdgeInsets padding;
  final ValueChanged<WidgetKind> onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);

    // **Empty:** a card with the sentence and both add buttons
    // — never just a grey sentence.
    if (widgets.isEmpty) {
      return ListView(
        padding: padding,
        children: [
          _CardFrame(
            editing: false,
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Icon(HiwiskiSymbols.dashboard, color: context.scheme.primary),
                const SizedBox(height: HiwiskiMetrics.space10),
                Text(l.boardEmpty, style: context.texts.bodyLarge),
                const SizedBox(height: HiwiskiMetrics.space14),
                Wrap(
                  spacing: HiwiskiMetrics.space8,
                  runSpacing: HiwiskiMetrics.space8,
                  children: [
                    for (final kind in WidgetKind.forStartBoard)
                      OutlinedButton.icon(
                        icon: const Icon(
                          HiwiskiSymbols.add,
                          size: HiwiskiMetrics.icon18,
                        ),
                        label: Text(widgetKindLabel(l, kind)),
                        onPressed: () => onAdd(kind),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - padding.horizontal;
        final columns = (width / HiwiskiMetrics.gridMinWidget).floor().clamp(
          1,
          6,
        );
        // Staggered rather than masonry: a tile may span more than one column
        // (StartWidth) — the week overview needs the room.
        return SingleChildScrollView(
          padding: padding.add(const .only(bottom: HiwiskiMetrics.space32)),
          child: StaggeredGrid.count(
            crossAxisCount: columns,
            mainAxisSpacing: HiwiskiMetrics.space14,
            crossAxisSpacing: HiwiskiMetrics.space14,
            children: [
              for (final widget in widgets)
                StaggeredGridTile.fit(
                  crossAxisCellCount: StartWidth.of(
                    WidgetConfig.decode(widget.config),
                    WidgetKind.tryParse(widget.kind),
                  ).span(columns),
                  child: _Card(widget: widget, editing: editing),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The frame of a tile: `sf1`, radius 20, line `outlv` — in edit mode
/// **dashed** in `outl`.
class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.editing, required this.child, this.onTap});

  final bool editing;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    const radius = BorderRadius.all(.circular(HiwiskiMetrics.radiusWidget));
    final body = Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: editing
            ? BorderSide.none
            : BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: .antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const .all(HiwiskiMetrics.space16),
          child: child,
        ),
      ),
    );
    return editing ? DashedBorder(color: scheme.outline, child: body) : body;
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.widget, required this.editing});

  final BoardWidget widget;
  final bool editing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final kind = WidgetKind.tryParse(widget.kind);
    final title = kind == null ? widget.kind : widgetKindLabel(l, kind);
    final scheme = context.scheme;

    return _CardFrame(
      editing: editing,
      // Tapping the card leads into the module; in edit mode it opens its
      // configuration.
      onTap: editing
          ? () =>
                showWidgetConfigSheet(context, widget: widget, startBoard: true)
          : () => openWidgetTarget(context, widget),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Row(
            children: [
              Icon(
                _icon(kind),
                size: HiwiskiMetrics.icon20,
                color: scheme.primary,
              ),
              const SizedBox(width: HiwiskiMetrics.space8),
              Expanded(
                child: Text(
                  title,
                  style: context.texts.labelLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: .w600,
                  ),
                ),
              ),
              if (editing) ...[
                IconButton.filledTonal(
                  iconSize: HiwiskiMetrics.icon20,
                  tooltip: l.boardConfigure,
                  icon: const Icon(HiwiskiSymbols.tune),
                  onPressed: () => showWidgetConfigSheet(
                    context,
                    widget: widget,
                    startBoard: true,
                  ),
                ),
                IconButton(
                  iconSize: HiwiskiMetrics.icon20,
                  color: scheme.error,
                  tooltip: l.actionDelete,
                  icon: const Icon(HiwiskiSymbols.delete),
                  onPressed: () => ref
                      .read(startViewModelProvider.notifier)
                      .deleteWidget(widget),
                ),
              ] else
                Icon(
                  HiwiskiSymbols.chevronRight,
                  size: HiwiskiMetrics.icon20,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
          const SizedBox(height: HiwiskiMetrics.space10),
          WidgetTile(widget: widget, interactive: !editing),
          const SizedBox(height: HiwiskiMetrics.space10),
          WidgetSummary(widget: widget),
        ],
      ),
    );
  }

  static IconData _icon(WidgetKind? kind) => switch (kind) {
    .clock => HiwiskiSymbols.schedule,
    .calendar => HiwiskiSymbols.event,
    .calendarWeek => HiwiskiSymbols.viewWeek,
    .todoLists || .todoList => HiwiskiSymbols.checklist,
    .shoppingList => HiwiskiSymbols.shoppingCart,
    .kanbanBoard => HiwiskiSymbols.viewKanban,
    .recipe => HiwiskiSymbols.restaurant,
    .wikiPage => HiwiskiSymbols.menuBook,
    .note => HiwiskiSymbols.description,
    _ => HiwiskiSymbols.help,
  };
}
