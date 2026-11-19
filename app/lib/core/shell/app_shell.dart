import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../routing/routes.dart';
import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_symbols.dart';
import '../theme/hiwiski_tokens.dart';
import '../ui/content_width.dart';
import '../ui/pull_hint.dart';
import 'breakpoints.dart';
import 'shell_view_model.dart';

/// The navigation scaffold: **Start · Calendar · Tasks · Wiki.** Nothing more.
///
/// Everything else is a subscreen of one of these four or sits behind account and
/// search. Search is not an area but an icon in the header — it is a springboard, not
/// a place to stay.
///
/// | Width | Navigation |
/// | --- | --- |
/// | < 600 | tab bar at the bottom, 80 high |
/// | 600–1023 | navigation rail on the left, 80 wide |
/// | ≥ 1024 | drawer on the left, 260 wide, collapsible to 80 |
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  List<_Destination> _destinations(BuildContext context) {
    final l = L.of(context);
    return [
      _Destination(
        HiwiskiSymbols.dashboard,
        l.navHome,
        const HomeRoute().location,
      ),
      _Destination(
        HiwiskiSymbols.calendarMonth,
        l.navCalendar,
        const CalendarRoute().location,
      ),
      _Destination(
        HiwiskiSymbols.taskAlt,
        l.navTasks,
        const TodoRoute().location,
      ),
      _Destination(
        HiwiskiSymbols.menuBook,
        l.navWiki,
        const WikiRoute().location,
      ),
    ];
  }

  /// A subscreen counts toward its area: whoever is in a task's detail sees "Tasks"
  /// highlighted, not nothing at all.
  ///
  /// `null` where no area matches — search, account: it fell back to "Start", which
  /// then looked selected, and tapping it seemed to do nothing while it navigated
  /// away.
  int? _selectedIndex(List<_Destination> destinations) {
    int? best;
    int bestLength = 0;
    for (int i = 0; i < destinations.length; i++) {
      final path = destinations[i].path;
      final matches = path == '/'
          ? location == '/'
          : location == path || location.startsWith('$path/');
      if (matches && path.length >= bestLength) {
        best = i;
        bestLength = path.length;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakpoint = Breakpoint.of(context);
    final destinations = _destinations(context);
    final selected = _selectedIndex(destinations);
    // The bar needs an index; with none selected it shows the first without a mark.
    final none = selected == null;

    final areas = ref.watch(shellViewModelProvider).areaLocations;

    /// An area chosen: the one already open goes back to its start; another
    /// returns to where it was left, if areas keep their page (Account →
    /// Customize) — and the area left is remembered for the next time.
    void go(int index) {
      final router = GoRouter.of(context);
      final start = destinations[index].path;
      if (selected == index) {
        ref.read(shellViewModelProvider.notifier).resetArea(index);
        router.go(start);
        return;
      }
      if (selected case final from?) {
        ref
            .read(shellViewModelProvider.notifier)
            .leaveArea(
              from,
              router.routerDelegate.currentConfiguration.uri.toString(),
            );
      }
      final back = areas[index];
      if (back == null) {
        router.go(start);
        return;
      }
      // On the phone a wiki page lies on top of the tree: laid there again, so that
      // "Back" leads to the tree as it did before.
      final pageId = WikiRoute.pageIdOf(Uri.parse(back));
      if (pageId != null && breakpoint.isCompact) {
        router.go(start);
        // The pushed page lives until it is popped; nothing waits for that.
        unawaited(router.push<void>(WikiRoute(pageId: pageId).location));
        return;
      }
      router.go(back);
    }

    // What is left beside the navigation: the info bar asks it before it stands
    // beside the content.
    final content = PullHint(
      show: ref.watch(shellViewModelProvider.select((s) => s.showPullHint)),
      onPulled: () =>
          unawaited(ref.read(shellViewModelProvider.notifier).recordPull()),
      child: ContentWidth(child: _FirstPull(child: child)),
    );
    // The drawer only from 1200: an iPad upright (1032) is wide, but with the drawer's
    // 260 beside it the wiki's article was left a strip. Below that the rail.
    final drawer =
        MediaQuery.sizeOf(context).width >= HiwiskiMetrics.breakpointDrawer;

    // One Scaffold for every width: the root for snackbars and the keyboard inset.
    // Only the navigation next to or below the content changes.
    return Scaffold(
      body: switch ((breakpoint, drawer)) {
        (.compact, _) => SafeArea(bottom: false, child: content),
        (.medium, _) || (.wide, false) => SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: selected,
                onDestinationSelected: go,
                leading: IconButton(
                  icon: const Icon(HiwiskiSymbols.search),
                  tooltip: L.of(context).searchTitle,
                  onPressed: () => const SearchRoute().go(context),
                ),
                destinations: [
                  for (final destination in destinations)
                    NavigationRailDestination(
                      icon: Icon(destination.icon, fill: 0),
                      selectedIcon: Icon(destination.icon, fill: 1),
                      label: Text(destination.label),
                    ),
                ],
              ),
              Expanded(child: content),
            ],
          ),
        ),
        (.wide, true) => SafeArea(
          child: Row(
            children: [
              _WideDrawer(
                destinations: destinations,
                selected: selected ?? -1,
                location: location,
                expanded: ref.watch(shellViewModelProvider).drawerExpanded,
                onSelect: go,
                // The drawer remembers its state.
                onToggle: () => unawaited(
                  ref.read(shellViewModelProvider.notifier).toggleDrawer(),
                ),
              ),
              Expanded(child: content),
            ],
          ),
        ),
      },
      bottomNavigationBar: breakpoint.isCompact
          ? NavigationBar(
              selectedIndex: selected ?? 0,
              indicatorColor: none ? Colors.transparent : null,
              onDestinationSelected: go,
              destinations: [
                for (final destination in destinations)
                  NavigationDestination(
                    // FILL 1 for selected — the only state indicator on a symbol in
                    // the whole design.
                    icon: Icon(destination.icon, fill: 0),
                    selectedIcon: Icon(destination.icon, fill: none ? 0 : 1),
                    label: destination.label,
                  ),
              ],
            )
          : null,
    );
  }
}

/// **In the browser: first the snapshot, then the content.**
///
/// There the database lives in memory only, and every page load starts empty. Without
/// this every screen would say "Nothing here yet" for a moment — and that would be a
/// lie. On the device the state from last time is there; it is not needed there.
///
/// Only while the first run is going: if it fails, the content shows what is wrong
/// with its banner instead of loading forever.
class _FirstPull extends ConsumerWidget {
  const _FirstPull({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kIsWeb) return child;
    final waiting = ref.watch(shellViewModelProvider).waitingForFirstSync;
    if (!waiting) return child;
    return Center(
      child: Semantics(
        label: L.of(context).stateLoading,
        child: const CircularProgressIndicator(),
      ),
    );
  }
}

class const _Destination(
  final IconData icon,
  final String label,
  final String path,
);

/// The drawer is **not a `Drawer` in the pull-out sense** but a fixed column next to the
/// content — and it can be collapsed to 80.
///
/// At the top the header from the design: collapse, the family name, search.
/// Collapsed, the icons and search remain. At the bottom family and
/// settings — they are highlighted too when you are there.
class _WideDrawer extends ConsumerWidget {
  const _WideDrawer({
    required this.destinations,
    required this.selected,
    required this.location,
    required this.expanded,
    required this.onSelect,
    required this.onToggle,
  });

  final List<_Destination> destinations;
  final int selected;
  final String location;
  final bool expanded;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggle;

  bool _under(String path) => location == path || location.startsWith('$path/');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final scheme = context.scheme;
    final shell = ref.watch(shellViewModelProvider);
    final familyName = shell.familyName.isEmpty ? l.appName : shell.familyName;

    final inFamily = _under(const FamilyRoute().location);
    final inAccount = !inFamily && _under(const AccountRoute().location);
    final inSearch = _under(const SearchRoute().location);
    final mainSelected = inFamily || inAccount || inSearch ? -1 : selected;

    final toggle = IconButton(
      icon: Icon(expanded ? HiwiskiSymbols.menuOpen : HiwiskiSymbols.menu),
      color: scheme.onSurfaceVariant,
      onPressed: onToggle,
      tooltip: expanded ? l.navCollapse : l.navExpand,
    );
    final search = IconButton(
      icon: const Icon(HiwiskiSymbols.search),
      color: scheme.onSurfaceVariant,
      onPressed: () => const SearchRoute().go(context),
      tooltip: l.searchTitle,
    );

    // The color sits on the `Material` and not on the `AnimatedContainer`: otherwise it
    // fades along over 200 ms on a theme change, and when the signed-in member changed
    // the column visibly stayed light while the content was already dark.
    // The width is what should animate, not the theme.
    return Material(
      color: scheme.surfaceContainerLow,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: expanded
            ? HiwiskiMetrics.drawerWidth
            : HiwiskiMetrics.drawerCollapsedWidth,
        padding: const .symmetric(
          vertical: HiwiskiMetrics.space20,
          horizontal: HiwiskiMetrics.space12,
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Padding(
              padding: const .only(bottom: HiwiskiMetrics.space16),
              child: expanded
                  ? Row(
                      children: [
                        toggle,
                        const SizedBox(width: HiwiskiMetrics.space6),
                        Expanded(
                          child: Text(
                            familyName,
                            maxLines: 1,
                            overflow: .ellipsis,
                            style: context.texts.titleSmall,
                          ),
                        ),
                        search,
                      ],
                    )
                  : Column(
                      spacing: HiwiskiMetrics.space4,
                      children: [toggle, search],
                    ),
            ),
            for (var i = 0; i < destinations.length; i++)
              _DrawerRow(
                destination: destinations[i],
                selected: i == mainSelected,
                expanded: expanded,
                onTap: () => onSelect(i),
              ),
            const Spacer(),
            if (shell.hasFamily)
              _DrawerRow(
                destination: _Destination(
                  HiwiskiSymbols.group,
                  l.navFamily,
                  const FamilyRoute().location,
                ),
                selected: inFamily,
                expanded: expanded,
                onTap: () => const FamilyRoute().go(context),
              ),
            _DrawerRow(
              destination: _Destination(
                HiwiskiSymbols.settings,
                l.settingsTitle,
                const AccountRoute().location,
              ),
              selected: inAccount,
              expanded: expanded,
              onTap: () => const AccountRoute().go(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerRow extends StatelessWidget {
  const _DrawerRow({
    required this.destination,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusSearch)),
        child: Container(
          height: HiwiskiMetrics.searchHeight,
          padding: .symmetric(
            horizontal: expanded ? HiwiskiMetrics.space16 : 0,
          ),
          decoration: BoxDecoration(
            color: selected ? scheme.secondaryContainer : Colors.transparent,
            borderRadius: const .all(.circular(HiwiskiMetrics.radiusSearch)),
          ),
          child: Row(
            mainAxisAlignment: expanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Icon(
                destination.icon,
                fill: selected ? 1 : 0,
                color: selected
                    ? scheme.onSecondaryContainer
                    : scheme.onSurface,
              ),
              if (expanded) ...[
                const SizedBox(width: HiwiskiMetrics.space12),
                Expanded(
                  child: Text(
                    destination.label,
                    overflow: .ellipsis,
                    style: context.texts.bodyLarge?.copyWith(
                      color: selected
                          ? scheme.onSecondaryContainer
                          : scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
