import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../domain/board/board_items.dart';
import '../../../../domain/board/widget_kinds.dart';
import '../widget_tile_view_model.dart';
import 'widget_tile.dart';

/// The footer of a tile: "Mum, Dad, Kids · 3 days", "3 lists".
class WidgetSummary extends ConsumerWidget {
  const WidgetSummary({super.key, required this.widget});

  final BoardWidget widget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final config = WidgetConfig.decode(widget.config);
    final summary =
        ref
            .watch(tileSummaryViewModelProvider(widget.kind, widget.config))
            .value ??
        const TileSummaryState();
    String calendars(String days) =>
        '${summary.calendars.isEmpty ? l.widgetNoCalendars : summary.calendars.join(', ')} · $days';
    final text = switch (WidgetKind.tryParse(widget.kind)) {
      .calendar => calendars(
        rangeLabel(l, config.intOr(WidgetConfigKeys.days, 3)),
      ),
      .calendarWeek => calendars(
        l.widgetWeekDaysCount(config.intOr(WidgetConfigKeys.days, 7)),
      ),
      // "Move · Doing" — the board, and the column if only one is shown.
      .kanbanBoard when summary.board != null => [
        ?summary.board,
        ?summary.column,
      ].join(' · '),
      .todoLists => l.widgetListCount(summary.lists),
      _ => null,
    };
    if (text == null) return const SizedBox.shrink();
    return Text(
      text,
      style: context.texts.labelSmall?.copyWith(
        color: context.scheme.onSurfaceVariant,
      ),
    );
  }
}
