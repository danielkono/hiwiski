import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/shell/breakpoints.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/color_tokens.dart';
import '../../../../core/ui/page_header.dart';
import '../../../../core/ui/period_swipe.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../../../core/ui/states.dart';
import '../../../../domain/calendar/calendar_kinds.dart';
import '../../../../domain/common/calendar_days.dart';
import '../../event_sheet/view/event_sheet.dart';
import '../calendar_overview_view_model.dart';
import 'day_list.dart';
import 'month_grid.dart';
import 'pinned_strip.dart';
import 'week_view.dart';

/// The calendar overview.
///
/// Filter bar, view menu, pinned strip, below it the list or the month.
class CalendarOverviewScreen extends ConsumerWidget {
  const CalendarOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = PageHeader(title: L.of(context).navCalendar);
    return ref
        .watch(calendarOverviewViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(header: header, error: error),
          data: (state) => _CalendarOverviewPage(state: state),
        );
  }

  /// Next to the avatar: the view menu and the way to manage the calendars. In the
  /// header, not after the tag chips — there they made the filter bar taller than on
  /// every other page, and switching to the calendar jumped.
  static List<Widget> _headerControls(
    BuildContext context,
    CalendarOverviewState state,
  ) => [
    _ViewMenu(state: state),
    IconButton(
      icon: const Icon(HiwiskiSymbols.settings),
      tooltip: L.of(context).calManage,
      onPressed: () => const ManageCalendarsRoute().go(context),
    ),
  ];
}

class _CalendarOverviewPage extends ConsumerWidget {
  const _CalendarOverviewPage({required this.state});

  final CalendarOverviewState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final padding = Breakpoint.of(context).pagePadding;

    return HiwiskiPage(
      header: PageHeader(
        title: l.navCalendar,
        trailing: CalendarOverviewScreen._headerControls(context, state),
      ),
      filter: TagPageFilter(
        tags: state.tags,
        selected: state.filter,
        onToggle: (id) =>
            ref.read(calendarOverviewViewModelProvider.notifier).toggleTag(id),
        onClear: () =>
            ref.read(calendarOverviewViewModelProvider.notifier).clearTags(),
      ),
      // No calendar yet: an event would have nowhere to go, so the first step is
      // a calendar.
      body: state.empty
          ? EmptyState(
              icon: HiwiskiSymbols.calendarMonth,
              message: l.calEmpty,
              actionLabel: l.calNewCalendar,
              onAction: () =>
                  const ManageCalendarsRoute(newCalendar: true).go(context),
            )
          : _Body(padding: padding, state: state),
      // The FAB only appears on the task and calendar overviews.
      // Only subscribed or imported calendars: it offers a calendar
      // of one's own, since an event would have nowhere to go.
      floatingActionButton: switch ((state.empty, state.takesEvents)) {
        (true, _) => null,
        (false, true) => FloatingActionButton.extended(
          onPressed: () => showEventSheet(context, day: state.selectedDay),
          icon: const Icon(HiwiskiSymbols.add),
          label: Text(l.calNewEvent),
        ),
        (false, false) => FloatingActionButton.extended(
          onPressed: () =>
              const ManageCalendarsRoute(newCalendar: true).go(context),
          icon: const Icon(HiwiskiSymbols.add),
          label: Text(l.calNewCalendarShort),
        ),
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.padding, required this.state});

  final EdgeInsets padding;
  final CalendarOverviewState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calendars = state.calendarsById;
    final pinnedToday = state.pinnedToday;

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        // "Pinned strip at the top for all-day and multi-day events — once with
        // from–to, not again on every day."
        if (pinnedToday.isNotEmpty)
          PinnedStrip(
            occurrences: pinnedToday,
            calendars: calendars,
            padding: padding,
          ),
        Expanded(
          child: switch (state.mode) {
            .list => DayList(
              occurrences: state.timed,
              pinned: state.pinned,
              tasks: state.tasks,
              calendars: calendars,
              padding: padding,
              from: state.from,
              to: addDays(clock.now(), 60),
            ),
            // Swiped sideways like the arrows in their header.
            .week => PeriodSwipe(
              onShift: (weeks) => ref
                  .read(calendarOverviewViewModelProvider.notifier)
                  .shiftWeek(weeks),
              child: WeekView(
                state: state,
                occurrences: state.occurrences,
                calendars: calendars,
                padding: padding,
              ),
            ),
            .month => PeriodSwipe(
              onShift: (months) => ref
                  .read(calendarOverviewViewModelProvider.notifier)
                  .shiftMonth(months),
              child: MonthGrid(
                state: state,
                occurrences: state.occurrences,
                calendars: calendars,
                padding: padding,
                pinnedStrip: state.pinnedStrip,
              ),
            ),
          },
        ),
      ],
    );
  }
}

/// The view menu in the header: the pill with symbol, label and
/// `arrow_drop_down`.
class _ViewMenu extends ConsumerWidget {
  const _ViewMenu({required this.state});

  final CalendarOverviewState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final view = state;
    final calendars = state.calendars;
    final tokens = context.tokens;

    return MenuAnchor(
      menuChildren: [
        _MenuLabel(l.calViewSection),
        for (final entry in {
          CalendarViewMode.list: (l.calViewList, HiwiskiSymbols.viewList),
          CalendarViewMode.week: (l.calViewWeek, HiwiskiSymbols.viewWeek),
          CalendarViewMode.month: (
            l.calViewMonth,
            HiwiskiSymbols.calendarMonth,
          ),
        }.entries)
          MenuItemButton(
            leadingIcon: Icon(
              view.mode == entry.key
                  ? HiwiskiSymbols.radioButtonChecked
                  : HiwiskiSymbols.radioButtonUnchecked,
            ),
            onPressed: () => ref
                .read(calendarOverviewViewModelProvider.notifier)
                .setMode(entry.key),
            child: Text(entry.value.$1),
          ),
        const Divider(height: HiwiskiMetrics.space8),
        _MenuLabel(l.calCalendarsSection),
        for (final calendar in calendars)
          MenuItemButton(
            leadingIcon: Icon(
              view.hidden.contains(calendar.id)
                  ? HiwiskiSymbols.checkBoxOutlineBlank
                  : HiwiskiSymbols.checkBox,
              color: tokens.accent(accentOf(calendar.colorToken)),
            ),
            // Subscribed calendars carry a lock.
            trailingIcon: isLockedCalendar(calendar.kind)
                ? const Icon(HiwiskiSymbols.lock, size: HiwiskiMetrics.icon16)
                : null,
            onPressed: () => ref
                .read(calendarOverviewViewModelProvider.notifier)
                .toggleCalendar(calendar.id),
            child: Text(calendar.name),
          ),
      ],
      builder: (context, anchor, _) {
        void toggle() => anchor.isOpen ? anchor.close() : anchor.open();
        final icon = switch (view.mode) {
          .list => HiwiskiSymbols.viewList,
          .week => HiwiskiSymbols.viewWeek,
          .month => HiwiskiSymbols.calendarMonth,
        };
        final label = switch (view.mode) {
          .list => l.calViewList,
          .week => l.calViewWeek,
          .month => l.calViewMonth,
        };
        // On the phone the pill took the title's room in the header and pushed it
        // onto a second line: there the symbol alone, the label in the tooltip.
        if (Breakpoint.of(context).isCompact) {
          return IconButton(
            icon: Icon(icon),
            tooltip: label,
            onPressed: toggle,
          );
        }
        return ActionChip(
          avatar: Icon(icon, size: HiwiskiMetrics.icon18),
          label: Row(
            mainAxisSize: .min,
            children: [
              Text(label),
              const Icon(
                HiwiskiSymbols.arrowDropDown,
                size: HiwiskiMetrics.icon18,
              ),
            ],
          ),
          onPressed: toggle,
        );
      },
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .fromLTRB(
      HiwiskiMetrics.space12,
      HiwiskiMetrics.space8,
      HiwiskiMetrics.space12,
      HiwiskiMetrics.space4,
    ),
    child: Text(text, style: context.tokens.text.sectionLabel),
  );
}
