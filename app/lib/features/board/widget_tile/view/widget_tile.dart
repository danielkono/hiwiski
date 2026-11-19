import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/common/date_patterns.dart';
import '../../../../core/common/wire.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/color_tokens.dart';
import '../../../../core/ui/list_kind_tile.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../../../core/ui/thin_progress.dart';
import '../../../../core/ui/week_timeline.dart';
import '../../../../domain/board/board_items.dart';
import '../../../../domain/board/widget_kinds.dart';
import '../../../../domain/calendar/calendar_items.dart';
import '../../../../domain/calendar/occurrence.dart';
import '../../../../domain/common/calendar_days.dart';
import '../../../../domain/todo/kanban.dart';
import '../../../../domain/todo/todo_items.dart';
import '../../../../domain/todo/todo_models.dart';
import '../../../../domain/wiki/wiki_models.dart' show formatAmount;
import '../../../../domain/wiki/wiki_page.dart';
import '../../view/board_keys.dart';
import '../widget_tile_view_model.dart';

/// The content of a tile, depending on its kind.
///
/// **An unknown widget type shows a placeholder and never crashes** — an
/// installed app can be older than the server. That is why
/// there is exactly one place where the kind is resolved, and it always ends with
/// a widget.
class WidgetTile extends ConsumerWidget {
  const WidgetTile({
    super.key,
    required this.widget,
    this.kiosk = false,
    this.interactive = false,
  });

  final BoardWidget widget;

  /// Whether rows in the tile can be tapped — yes on the start board, not on the wall
  /// tablet: there is no app there for a tap to lead into.
  final bool interactive;

  /// On the wall tablet: larger text, more contrast, no controls.
  final bool kiosk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = WidgetConfig.decode(widget.config);
    final kind = WidgetKind.tryParse(widget.kind);

    return switch (kind) {
      null => const _Unknown(),
      .clock => _Clock(config: config, kiosk: kiosk),
      .calendar => _Calendar(config: config, kiosk: kiosk),
      .calendarWeek => _CalendarWeek(config: config, kiosk: kiosk),
      .todoLists => _TodoLists(config: config, interactive: interactive),
      .todoList || .shoppingList => _TodoList(config: config),
      .kanbanBoard => _KanbanTile(
        config: config,
        interactive: interactive,
        kiosk: kiosk,
      ),
      .wikiPage => _WikiPage(config: config),
      .note => _Note(config: config, kiosk: kiosk),
      .recipe => _Recipe(config: config),
      _ => const _Unknown(),
    };
  }
}

/// "Your app version does not know this widget yet."
class _Unknown extends StatelessWidget {
  const _Unknown();

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Row(
      spacing: HiwiskiMetrics.space10,
      children: [
        Icon(
          HiwiskiSymbols.help,
          size: HiwiskiMetrics.icon20,
          color: context.scheme.onSurfaceVariant,
        ),
        Expanded(
          child: Text(
            l.boardUnknownWidget,
            style: context.texts.bodySmall?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock({required this.config, required this.kiosk});

  final WidgetConfig config;
  final bool kiosk;

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  final DateTime _now = clock.now();
  Stream<DateTime>? _ticks;

  @override
  void initState() {
    super.initState();
    // A stream instead of a timer: it ends with the widget, and a clock that keeps running
    // after closing keeps the screen awake without anyone seeing it.
    _ticks = Stream.periodic(const Duration(seconds: 1), (_) => clock.now());
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final seconds = widget.config.boolOr(WidgetConfigKeys.seconds, false);
    final hour24 = widget.config.boolOr(WidgetConfigKeys.hour24, true);
    final showDate = widget.config.boolOr(WidgetConfigKeys.date, true);

    return StreamBuilder<DateTime>(
      stream: _ticks,
      initialData: _now,
      builder: (context, snapshot) {
        final now = snapshot.data ?? _now;
        final pattern = switch ((hour24, seconds)) {
          (true, true) => DatePatterns.time24Seconds,
          (true, false) => DatePatterns.time24,
          (false, true) => DatePatterns.time12Seconds,
          (false, false) => DatePatterns.time12,
        };
        return Column(
          crossAxisAlignment: .start,
          children: [
            Text(
              DateFormat(pattern, locale).format(now),
              style:
                  (widget.kiosk
                          ? context.texts.displayLarge
                          : context.texts.displaySmall)
                      ?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
            ),
            if (showDate)
              Text(
                DateFormat.yMMMMEEEEd(locale).format(now),
                style: context.texts.bodyMedium?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Calendar extends ConsumerWidget {
  const _Calendar({required this.config, required this.kiosk});

  final WidgetConfig config;
  final bool kiosk;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(calendarTileViewModelProvider(config.encode(), week: false))
      .when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (error, _) => NoticeBar.failure(context, error: error),
        data: (tile) => _tile(context, tile),
      );

  Widget _tile(BuildContext context, CalendarTileState tile) {
    final l = L.of(context);
    final locale = Localizations.localeOf(context).toString();
    final calendars = tile.calendars;
    final occurrences = tile.occurrences;
    final today = startOfDay(clock.now());

    if (occurrences.isEmpty) {
      return Padding(
        padding: const .symmetric(vertical: HiwiskiMetrics.space6),
        child: Text(
          l.widgetNoEvents,
          style: context.texts.bodyMedium?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
      );
    }

    DateTime? lastDay;
    final rows = <Widget>[];
    for (final occurrence in occurrences.take(kiosk ? 12 : 8)) {
      final day = startOfDay(
        occurrence.start.isBefore(today) ? today : occurrence.start,
      );
      if (day != lastDay) {
        rows.add(
          Padding(
            padding: .only(
              top: lastDay == null
                  ? HiwiskiMetrics.space2
                  : HiwiskiMetrics.space8,
              bottom: HiwiskiMetrics.space4,
            ),
            child: Text(
              dayLabel(l, locale, day),
              style:
                  (kiosk ? context.texts.titleSmall : context.texts.labelMedium)
                      ?.copyWith(
                        color: context.scheme.onSurfaceVariant,
                        fontWeight: .w600,
                      ),
            ),
          ),
        );
        lastDay = day;
      }
      rows.add(
        _EventLine(
          occurrence: occurrence,
          calendar: calendars[occurrence.event.calendarId],
          locale: locale,
          kiosk: kiosk,
        ),
      );
    }

    return Column(crossAxisAlignment: .stretch, children: rows);
  }
}

/// The week overview: from today on, the days side by side — what each holds and how
/// its events stand to each other, at a glance.
class _CalendarWeek extends ConsumerWidget {
  const _CalendarWeek({required this.config, required this.kiosk});

  final WidgetConfig config;
  final bool kiosk;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(calendarTileViewModelProvider(config.encode(), week: true))
      .when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (error, _) => NoticeBar.failure(context, error: error),
        data: _tile,
      );

  Widget _tile(CalendarTileState tile) {
    return WeekTimeline(
      days: tile.days,
      occurrences: tile.occurrences,
      calendars: tile.calendars,
      // A tile has no height of its own to fit into; this one shows a working day.
      height: kiosk
          ? HiwiskiMetrics.weekTimelineHeightKiosk
          : HiwiskiMetrics.weekTimelineHeight,
      kiosk: kiosk,
    );
  }
}

/// "Today", "Tomorrow", otherwise "Tue, 29.09." — as in the design.
String dayLabel(L l, String locale, DateTime day) {
  final today = startOfDay(clock.now());
  if (day == today) return l.calToday;
  if (day == addDays(today, 1)) return l.calTomorrow;
  return '${DateFormat.E(locale).format(day)}, ${DateFormat(DatePatterns.dayMonth, locale).format(day)}';
}

class _EventLine extends StatelessWidget {
  const _EventLine({
    required this.occurrence,
    required this.calendar,
    required this.locale,
    required this.kiosk,
  });

  final Occurrence occurrence;
  final Calendar? calendar;
  final String locale;
  final bool kiosk;

  @override
  Widget build(BuildContext context) {
    final color = context.tokens.accent(
      accentOf(calendar?.colorToken ?? ColorTokens.blue),
    );
    final muted = context.scheme.onSurfaceVariant;

    // Strip 4×32 · time 44 · title 15/500 · calendar name on the right.
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: kiosk
            ? HiwiskiMetrics.tileRowHeightKiosk
            : HiwiskiMetrics.tileRowHeight,
      ),
      child: Row(
        children: [
          Container(
            width: HiwiskiMetrics.calendarStripeWidth,
            height: kiosk
                ? HiwiskiMetrics.calendarStripeHeightKiosk
                : HiwiskiMetrics.calendarStripeHeight,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const .all(.circular(HiwiskiMetrics.space2)),
            ),
          ),
          const SizedBox(width: HiwiskiMetrics.space12),
          SizedBox(
            width: kiosk
                ? HiwiskiMetrics.eventTimeColumnWidthKiosk
                : HiwiskiMetrics.eventTimeColumnWidth,
            child: Text(
              occurrence.allDay
                  ? ''
                  : DateFormat.Hm(locale).format(occurrence.start),
              style:
                  (kiosk ? context.texts.titleMedium : context.texts.bodyMedium)
                      ?.copyWith(color: muted),
            ),
          ),
          Expanded(
            child: Text(
              occurrence.event.title,
              overflow: .ellipsis,
              style:
                  (kiosk ? context.texts.titleLarge : context.texts.bodyLarge)
                      ?.copyWith(fontWeight: .w500),
            ),
          ),
          if (calendar case final calendar? when !kiosk) ...[
            const SizedBox(width: HiwiskiMetrics.space8),
            Text(
              calendar.name,
              style: context.texts.labelSmall?.copyWith(color: muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Shows lists, not individual tasks."
///
/// Per list: icon, title, "6 open" and the progress bar. Which lists is stored
/// in `listIds`; **if the key is missing, it is all of them** — so tiles from before
/// this setting stay as they were.
class _TodoLists extends ConsumerWidget {
  const _TodoLists({required this.config, required this.interactive});

  final WidgetConfig config;
  final bool interactive;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(listsTileViewModelProvider(config.encode()))
      .when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (error, _) => NoticeBar.failure(context, error: error),
        data: (tile) => _tile(context, tile),
      );

  Widget _tile(BuildContext context, ListsTileState tile) {
    final l = L.of(context);
    final lists = tile.lists;
    final muted = context.scheme.onSurfaceVariant;

    if (lists.isEmpty) {
      return Padding(
        padding: const .symmetric(vertical: HiwiskiMetrics.space6),
        child: Text(
          tile.anyList ? l.widgetNoListsChosen : l.widgetNothingToShow,
          style: context.texts.bodyMedium?.copyWith(color: muted),
        ),
      );
    }

    // **A single list shows its entries**, not just its status: whoever puts a single list
    // on the start board wants to check things off without opening it.
    if (lists.length == 1) {
      return _SingleList(
        config: config.encode(),
        summary: lists.single,
        interactive: interactive,
      );
    }

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        for (var i = 0; i < lists.length; i++)
          InkWell(
            onTap: interactive
                ? () => TodoListRoute(listId: lists[i].list.id).go(context)
                : null,
            child: Container(
              padding: const .symmetric(vertical: HiwiskiMetrics.space8),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: context.tokens.divider)),
              ),
              child: Column(
                crossAxisAlignment: .stretch,
                spacing: HiwiskiMetrics.space6,
                children: [
                  Row(
                    children: [
                      Icon(
                        listKindIcon(lists[i].list.kind),
                        size: HiwiskiMetrics.icon20,
                        color: muted,
                      ),
                      const SizedBox(width: HiwiskiMetrics.space10),
                      Expanded(
                        child: Text(
                          lists[i].list.name,
                          overflow: .ellipsis,
                          style: context.texts.bodyLarge?.copyWith(
                            fontWeight: .w500,
                          ),
                        ),
                      ),
                      Text(
                        l.widgetOpenCount(lists[i].open),
                        style: context.texts.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const .only(
                      left: HiwiskiMetrics.icon20 + HiwiskiMetrics.space10,
                    ),
                    child: ThinProgress(value: lists[i].progress),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A single selected list: header with name and "N open", the open entries
/// below — checkable where the tile is interactive, read-only otherwise.
///
/// A ticked entry does not vanish at once: it is struck through before one's eyes and
/// leaves two seconds later — long enough to see what was ticked, and to tap it again
/// if it was the wrong one. The tick itself is saved right away.
class _SingleList extends ConsumerStatefulWidget {
  const _SingleList({
    required this.config,
    required this.summary,
    required this.interactive,
  });

  /// The tile's configuration — what its ViewModel is keyed by.
  final String config;
  final TodoListSummary summary;
  final bool interactive;

  @override
  ConsumerState<_SingleList> createState() => _SingleListState();
}

class _SingleListState extends ConsumerState<_SingleList> {
  static const _maxItems = 8;

  /// How long a ticked entry stays, struck through.
  static const _linger = Duration(seconds: 2);

  /// Ticked here and still on their way out, by id.
  final _leaving = <String, Timer>{};

  /// Where each leaving entry stood when it was ticked. A done task sorts to the
  /// bottom of its list; in the tile it stays put until it is gone — an entry jumping
  /// away under the finger made ticking the next one a hunt.
  final _positions = <String, int>{};

  /// The entries as last shown, top to bottom.
  var _shownIds = <String>[];

  @override
  void dispose() {
    for (final timer in _leaving.values) {
      timer.cancel();
    }
    super.dispose();
  }

  void _tap(Todo todo) {
    final timer = _leaving.remove(todo.id);
    if (timer != null) {
      // Tapped again while leaving: it was the wrong one.
      timer.cancel();
      setState(() => _positions.remove(todo.id));
      ref
          .read(listsTileViewModelProvider(widget.config).notifier)
          .setStatus(todo, false);
      return;
    }
    final leaving = Timer(_linger, () {
      if (!mounted) return;
      setState(() {
        _leaving.remove(todo.id);
        _positions.remove(todo.id);
      });
    });
    setState(() {
      _positions[todo.id] = _shownIds.indexOf(todo.id);
      _leaving[todo.id] = leaving;
    });
    ref
        .read(listsTileViewModelProvider(widget.config).notifier)
        .setStatus(todo, true);
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final interactive = widget.interactive;
    final l = L.of(context);
    final muted = context.scheme.onSurfaceVariant;
    final todos =
        ref.watch(listsTileViewModelProvider(widget.config)).value?.todos ??
        const <Todo>[];
    final open = todos
        .where(
          (todo) =>
              todo.status != TodoStatuses.done &&
              !_leaving.containsKey(todo.id),
        )
        .toList();
    // The leaving ones back where they stood, in the order they stood in.
    final leaving =
        todos.where((todo) => _leaving.containsKey(todo.id)).toList()..sort(
          (a, b) => (_positions[a.id] ?? 0).compareTo(_positions[b.id] ?? 0),
        );
    for (final todo in leaving) {
      final at = _positions[todo.id] ?? open.length;
      open.insert(at.clamp(0, open.length), todo);
    }
    final shown = open.take(_maxItems).toList();
    _shownIds = [for (final todo in shown) todo.id];

    final column = Column(
      crossAxisAlignment: .stretch,
      children: [
        InkWell(
          onTap: interactive
              ? () => TodoListRoute(listId: summary.list.id).go(context)
              : null,
          child: Padding(
            padding: const .symmetric(vertical: HiwiskiMetrics.space4),
            child: Row(
              children: [
                Icon(
                  listKindIcon(summary.list.kind),
                  size: HiwiskiMetrics.icon20,
                  color: muted,
                ),
                const SizedBox(width: HiwiskiMetrics.space10),
                Expanded(
                  child: Text(
                    summary.list.name,
                    overflow: .ellipsis,
                    style: context.texts.bodyLarge?.copyWith(fontWeight: .w500),
                  ),
                ),
                Text(
                  l.widgetOpenCount(summary.open),
                  style: context.texts.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ),
        if (shown.isEmpty)
          Padding(
            padding: const .symmetric(vertical: HiwiskiMetrics.space6),
            child: Text(
              l.widgetNothingToShow,
              style: context.texts.bodyMedium?.copyWith(color: muted),
            ),
          ),
        for (final todo in shown)
          InkWell(
            key: BoardKeys.widgetTodo(todo.id),
            onTap: interactive ? () => _tap(todo) : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: HiwiskiMetrics.tileRowHeight,
              ),
              child: _TodoLine(
                text: [
                  if (todo.amount case final amount?) formatAmount(amount),
                  ?todo.unit,
                  todo.title,
                ].join(' '),
                ticked: _leaving.containsKey(todo.id),
              ),
            ),
          ),
        if (open.length > shown.length)
          Padding(
            padding: const .only(top: HiwiskiMetrics.space4),
            child: Text(
              l.widgetMoreItems(open.length - shown.length),
              style: context.texts.bodySmall?.copyWith(color: muted),
            ),
          ),
      ],
    );
    // The tile closes up smoothly once a ticked entry has left.
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: column,
    );
  }
}

/// One entry: the box, and the text — struck through from left to right once ticked.
class _TodoLine extends StatelessWidget {
  const _TodoLine({required this.text, required this.ticked});

  final String text;
  final bool ticked;

  @override
  Widget build(BuildContext context) {
    final muted = context.scheme.onSurfaceVariant;
    return Row(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: Icon(
            ticked
                ? HiwiskiSymbols.checkBox
                : HiwiskiSymbols.checkBoxOutlineBlank,
            key: ValueKey(ticked),
            size: HiwiskiMetrics.icon20,
            color: ticked ? context.scheme.primary : muted,
          ),
        ),
        const SizedBox(width: HiwiskiMetrics.space10),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: ticked ? 1 : 0),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              builder: (context, progress, child) => Stack(
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 350),
                    style: (context.texts.bodyMedium ?? const TextStyle())
                        .copyWith(
                          color: ticked ? muted : context.scheme.onSurface,
                        ),
                    child: child ?? const SizedBox.shrink(),
                  ),
                  // The line grows across the text, as if drawn by hand.
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress,
                      child: Center(
                        child: Container(
                          height: HiwiskiMetrics.strokeBold,
                          color: muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              child: Text(text, overflow: .ellipsis, maxLines: 1),
            ),
          ),
        ),
      ],
    );
  }
}

String rangeLabel(L l, int days) => switch (days) {
  1 => l.widgetRangeToday,
  2 => l.widgetRangeTomorrow,
  7 => l.widgetRange7,
  14 => l.widgetRange14,
  _ => l.widgetRange3,
};

/// Where a tap on the tile leads: into the module it shows.
void openWidgetTarget(BuildContext context, BoardWidget widget) {
  final config = WidgetConfig.decode(widget.config);
  switch (WidgetKind.tryParse(widget.kind)) {
    case .calendar || .calendarWeek:
      const CalendarRoute().go(context);
    case .todoLists:
      const TodoRoute().go(context);
    case .todoList || .shoppingList || .kanbanBoard:
      final listId = config.get<String>(WidgetConfigKeys.listId);
      listId == null
          ? const TodoRoute().go(context)
          : TodoListRoute(listId: listId).go(context);
    case .wikiPage:
      WikiRoute(pageId: config.get<String>(WidgetConfigKeys.pageId))
          .go(context);
    case .recipe:
      WikiRoute(pageId: config.get<String>(WidgetConfigKeys.recipeId))
          .go(context);
    default:
      break;
  }
}

/// The open entries of **one** list.
class _TodoList extends ConsumerWidget {
  const _TodoList({required this.config});

  final WidgetConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final listId = config.get<String>(WidgetConfigKeys.listId);
    if (listId == null) {
      return Text(
        l.widgetNotConfigured,
        style: context.texts.bodyMedium?.copyWith(
          color: context.scheme.onSurfaceVariant,
        ),
      );
    }

    return ref
        .watch(listTileViewModelProvider(listId))
        .when(
          skipLoadingOnReload: true,
          loading: () => const SizedBox.shrink(),
          error: (error, _) => NoticeBar.failure(context, error: error),
          data: (tile) => tile == null
              ? const SizedBox.shrink()
              : _tile(context, ref, tile),
        );
  }

  Widget _tile(BuildContext context, WidgetRef ref, ListTileState tile) {
    final l = L.of(context);
    // An archived list stays on the board as a line, not as boxes nobody may tick
    // — the tile says where it went instead of going blank.
    if (tile.archived) {
      return Text(
        l.widgetListArchived,
        style: context.texts.bodyMedium?.copyWith(
          color: context.scheme.onSurfaceVariant,
        ),
      );
    }

    final todos = tile.todos;
    final showDone = config.boolOr(WidgetConfigKeys.showDone, false);
    final count = config.intOr(WidgetConfigKeys.count, 6);
    final shown = todos
        .where((todo) => showDone || todo.status != TodoStatuses.done)
        .take(count);

    if (shown.isEmpty) {
      return Text(
        l.widgetNothingToShow,
        style: context.texts.bodyMedium?.copyWith(
          color: context.scheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        for (final todo in shown)
          Padding(
            padding: const .symmetric(vertical: HiwiskiMetrics.space2),
            child: Row(
              spacing: HiwiskiMetrics.space8,
              children: [
                Icon(
                  todo.status == TodoStatuses.done
                      ? HiwiskiSymbols.checkBox
                      : HiwiskiSymbols.checkBoxOutlineBlank,
                  size: HiwiskiMetrics.icon18,
                  color: context.scheme.onSurfaceVariant,
                ),
                Expanded(
                  child: Text(
                    todo.title,
                    overflow: .ellipsis,
                    style: context.texts.bodyMedium?.copyWith(
                      // Done items sit struck through at the bottom.
                      decoration: todo.status == TodoStatuses.done
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _WikiPage extends ConsumerWidget {
  const _WikiPage({required this.config});

  final WidgetConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final pageId = config.get<String>(WidgetConfigKeys.pageId);
    if (pageId == null) {
      return Text(
        l.widgetNotConfigured,
        style: context.texts.bodyMedium?.copyWith(
          color: context.scheme.onSurfaceVariant,
        ),
      );
    }

    return ref
        .watch(pageTileViewModelProvider(pageId))
        .when(
          skipLoadingOnReload: true,
          loading: () => const SizedBox.shrink(),
          error: (error, _) => NoticeBar.failure(context, error: error),
          data: (page) =>
              page == null ? const SizedBox.shrink() : _tile(context, page),
        );
  }

  Widget _tile(BuildContext context, WikiPage page) {
    // The first paragraphs, not the whole page.
    final lines = page.content
        .split('\n')
        .where((line) => line.trim().isNotEmpty);
    return Text(
      lines.take(config.intOr(WidgetConfigKeys.lines, 4)).join('\n'),
      style: context.tokens.text.prose,
      overflow: .ellipsis,
      maxLines: config.intOr(WidgetConfigKeys.lines, 4) * 2,
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.config, required this.kiosk});

  final WidgetConfig config;
  final bool kiosk;

  @override
  Widget build(BuildContext context) => Text(
    config.get<String>(WidgetConfigKeys.text) ?? '',
    style: kiosk ? context.texts.titleLarge : context.tokens.text.prose,
  );
}

class _Recipe extends ConsumerWidget {
  const _Recipe({required this.config});

  final WidgetConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(recipeTileViewModelProvider(config.encode()))
        .when(
          skipLoadingOnReload: true,
          loading: () => const SizedBox.shrink(),
          error: (error, _) => NoticeBar.failure(context, error: error),
          data: (recipe) => _tile(context, ref, recipe),
        );
  }

  Widget _tile(BuildContext context, WidgetRef ref, WikiPage? recipe) {
    final l = L.of(context);
    if (recipe == null) {
      return Text(
        l.widgetNothingToShow,
        style: context.texts.bodyMedium?.copyWith(
          color: context.scheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: .start,
      children: [
        Text(recipe.title, style: context.texts.titleMedium),
        if (recipe.durationMinutes case final minutes?)
          Text(
            l.recipeMinutes(minutes),
            style: context.texts.bodySmall?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// A Kanban board on a board (widget directory): the whole board small —
/// per column name, count and the top cards — or the cards of one column.
class _KanbanTile extends ConsumerWidget {
  const _KanbanTile({
    required this.config,
    required this.interactive,
    required this.kiosk,
  });

  final WidgetConfig config;
  final bool interactive;
  final bool kiosk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final muted = context.scheme.onSurfaceVariant;
    Widget note(String text) =>
        Text(text, style: context.texts.bodyMedium?.copyWith(color: muted));

    final listId = config.get<String>(WidgetConfigKeys.listId);
    if (listId == null) return note(l.widgetNotConfigured);
    return ref
        .watch(listTileViewModelProvider(listId))
        .when(
          skipLoadingOnReload: true,
          loading: () => const SizedBox.shrink(),
          error: (error, _) => NoticeBar.failure(context, error: error),
          data: (tile) => tile == null
              ? const SizedBox.shrink()
              : _tile(context, ref, tile),
        );
  }

  Widget _tile(BuildContext context, WidgetRef ref, ListTileState tile) {
    final l = L.of(context);
    final muted = context.scheme.onSurfaceVariant;
    Widget note(String text) =>
        Text(text, style: context.texts.bodyMedium?.copyWith(color: muted));
    if (tile.archived) return note(l.widgetListArchived);
    final columns = tile.columns;
    if (columns.isEmpty) return note(l.widgetNotConfigured);
    final arranged = tile.cards;

    if (kanbanOneColumn(config)) {
      final column =
          columns
              .where(
                (c) => c.id == config.get<String>(WidgetConfigKeys.columnId),
              )
              .firstOrNull ??
          firstOpenColumnOf(columns);
      return _KanbanColumnList(
        column: column,
        cards: arranged[column.id]!,
        count: config.intOr(WidgetConfigKeys.count, 6),
        interactive: interactive,
      );
    }

    // Wide enough, the columns share the tile; otherwise they scroll sideways.
    return LayoutBuilder(
      builder: (context, constraints) {
        const minWidth = HiwiskiMetrics.kanbanMiniColumnWidth;
        const gap = HiwiskiMetrics.space8;
        final fitting =
            (constraints.maxWidth - gap * (columns.length - 1)) /
            columns.length;
        final width = fitting < minWidth ? minWidth : fitting;
        final row = Row(
          crossAxisAlignment: .start,
          children: [
            for (final (index, column) in columns.indexed) ...[
              if (index > 0) const SizedBox(width: gap),
              SizedBox(
                width: width,
                child: _KanbanMiniColumn(
                  column: column,
                  cards: arranged[column.id]!,
                  kiosk: kiosk,
                ),
              ),
            ],
          ],
        );
        final content = fitting < minWidth
            ? SingleChildScrollView(scrollDirection: .horizontal, child: row)
            : row;
        return interactive
            ? InkWell(
                onTap: () => TodoListRoute(listId: tile.list.id).go(context),
                child: content,
              )
            : content;
      },
    );
  }
}

/// One column, small: a color bar, name and count, the top three cards. The done
/// column shows only its count — what is done is done.
class _KanbanMiniColumn extends StatelessWidget {
  const _KanbanMiniColumn({
    required this.column,
    required this.cards,
    required this.kiosk,
  });

  final KanbanColumn column;
  final List<Todo> cards;
  final bool kiosk;

  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final muted = context.scheme.onSurfaceVariant;
    final accent = context.tokens.accent(accentOf(column.colorToken));
    final textStyle = kiosk ? context.texts.bodyLarge : context.texts.bodySmall;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Container(
          height: HiwiskiMetrics.barHeight,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: const .all(.circular(HiwiskiMetrics.radiusBar)),
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space6),
        Row(
          children: [
            if (column.done) ...[
              Icon(
                HiwiskiSymbols.checkCircle,
                size: HiwiskiMetrics.icon16,
                color: accent,
              ),
              const SizedBox(width: HiwiskiMetrics.space4),
            ],
            Expanded(
              child: Text(
                column.name,
                overflow: .ellipsis,
                style: context.texts.labelLarge,
              ),
            ),
            Text('${cards.length}', style: context.tokens.text.entityKey),
          ],
        ),
        if (!column.done) ...[
          for (final card in cards.take(_shown))
            Padding(
              padding: const .only(top: HiwiskiMetrics.space4),
              child: Text(
                card.title,
                maxLines: 2,
                overflow: .ellipsis,
                style: textStyle,
              ),
            ),
          if (cards.length > _shown)
            Padding(
              padding: const .only(top: HiwiskiMetrics.space4),
              child: Text(
                l.widgetKanbanMore(cards.length - _shown),
                style: textStyle?.copyWith(color: muted),
              ),
            ),
        ],
      ],
    );
  }
}

/// The cards of one column, without check boxes as on the board: a card's column says
/// whether it is done. Where the tile is interactive a tap opens the card.
class _KanbanColumnList extends ConsumerWidget {
  const _KanbanColumnList({
    required this.column,
    required this.cards,
    required this.count,
    required this.interactive,
  });

  final KanbanColumn column;
  final List<Todo> cards;
  final int count;
  final bool interactive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final muted = context.scheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Row(
          children: [
            Container(
              width: HiwiskiMetrics.dotSmall,
              height: HiwiskiMetrics.dotSmall,
              decoration: BoxDecoration(
                color: context.tokens.accent(accentOf(column.colorToken)),
                shape: .circle,
              ),
            ),
            const SizedBox(width: HiwiskiMetrics.space8),
            Expanded(child: Text(column.name, style: context.texts.titleSmall)),
            Text('${cards.length}', style: context.tokens.text.entityKey),
          ],
        ),
        const SizedBox(height: HiwiskiMetrics.space6),
        if (cards.isEmpty)
          Text(
            l.kanbanEmptyColumn,
            style: context.texts.bodyMedium?.copyWith(color: muted),
          ),
        for (final card in cards.take(count))
          InkWell(
            key: BoardKeys.widgetKanbanCard(card.id),
            onTap: interactive
                ? () => TodoDetailRoute(
                    listId: card.listId,
                    todoId: card.id,
                  ).go(context)
                : null,
            child: Padding(
              padding: const .symmetric(vertical: HiwiskiMetrics.space4),
              child: Text(
                card.title,
                maxLines: 1,
                overflow: .ellipsis,
                style: context.texts.bodyMedium,
              ),
            ),
          ),
        if (cards.length > count)
          Text(
            l.widgetKanbanMore(cards.length - count),
            style: context.texts.bodySmall?.copyWith(color: muted),
          ),
      ],
    );
  }
}
