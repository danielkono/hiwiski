import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../../../components/import/view/import_button.dart';
import '../../../../components/tags/view/tag_widgets.dart';
import '../../../../core/ui/panel_reopen.dart';
import '../../../../core/ui/panel_reopen_corner.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/shell/breakpoints.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/drag_auto_scroll.dart';
import '../../../../core/ui/embedded_page.dart';
import '../../../../core/ui/item_draggable.dart';
import '../../../../core/ui/list_kind_tile.dart';
import '../../../../core/ui/page_header.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../../../core/ui/states.dart';
import '../../../../core/ui/thin_progress.dart';
import '../../../../domain/todo/overview_view.dart';
import '../../../../domain/todo/todo_models.dart';
import '../../../../core/common/wire.dart';
import '../../list/view/todo_list_screen.dart';
import '../../new_list/view/new_list_sheet.dart';
import '../../view/todo_keys.dart';
import '../todo_overview_view_model.dart';

/// The task overview: a **card grid**, minimum width 280.
///
/// Per card: icon tile 40×40 in its own colour, title with mono number, count line,
/// progress bar.
class TodoOverviewScreen extends ConsumerWidget {
  const TodoOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = PageHeader(title: L.of(context).navTasks);
    return ref
        .watch(todoOverviewViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(header: header, error: error),
          data: (state) => _TodoOverviewPage(state: state),
        );
  }
}

class _TodoOverviewPage extends ConsumerWidget {
  const _TodoOverviewPage({required this.state});

  final TodoOverviewState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final padding = Breakpoint.of(context).pagePadding;

    // The order is the member's own: every list can be moved, filtered or not.
    void onMove(String id, String targetId) =>
        ref.read(todoOverviewViewModelProvider.notifier).move(id, targetId);
    final compact = Breakpoint.of(context).isCompact;

    return HiwiskiPage(
      header: PageHeader(
        title: l.navTasks,
        trailing: [
          const ImportButton(place: .todo),
          _ViewMenu(mode: state.mode),
        ],
      ),
      filter: TagPageFilter(
        tags: state.tags,
        selected: state.filter,
        onToggle: (id) =>
            ref.read(todoOverviewViewModelProvider.notifier).toggleTag(id),
        onClear: () =>
            ref.read(todoOverviewViewModelProvider.notifier).clearTags(),
      ),
      body: state.hasLists
          ? switch (state.mode) {
              .together => _ListGrid(
                lists: state.lists,
                padding: padding,
                onMove: onMove,
              ),
              .byKind => _KindGroups(
                groups: state.groups,
                padding: padding,
                onMove: onMove,
              ),
              // On the phone the rows are the screen; a list opens as its own.
              .sidebar when compact => _ListRows(
                lists: state.lists,
                selectedId: null,
                padding: padding,
                onOpen: (id) => TodoListRoute(listId: id).go(context),
                onMove: onMove,
              ),
              .sidebar => _SidebarLayout(state: state, onMove: onMove),
            }
          : EmptyState(
              icon: HiwiskiSymbols.checklist,
              message: l.todoEmpty,
              actionLabel: l.todoNewList,
              onAction: () => showNewListSheet(context),
            ),
      // The FAB only appears on the tasks and calendar overviews.
      // Inside a list there is the quick entry at the
      // bottom instead.
      // Next to an open list its quick entry is the way to add — the FAB would
      // cover it.
      floatingActionButton: state.mode == .sidebar && !compact
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showNewListSheet(context),
              icon: const Icon(HiwiskiSymbols.add),
              label: Text(l.todoNewList),
            ),
    );
  }
}

class _ListGrid extends StatefulWidget {
  const _ListGrid({
    required this.lists,
    required this.padding,
    required this.onMove,
  });

  final List<TodoListSummary> lists;
  final EdgeInsets padding;

  /// A card dropped on another takes its place; `null` while lists cannot be sorted.
  final void Function(String id, String targetId)? onMove;

  @override
  State<_ListGrid> createState() => _ListGridState();
}

class _ListGridState extends State<_ListGrid> {
  final _autoScroll = DragAutoScroll();

  @override
  void dispose() {
    _autoScroll.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = widget.padding;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - padding.horizontal;
        final columns = (width / HiwiskiMetrics.gridMinTodoList).floor().clamp(
          1,
          6,
        );
        final cardWidth =
            (width - (columns - 1) * HiwiskiMetrics.space12) / columns;
        // The cards have different heights — with and without tags —, hence masonry and
        // no fixed aspect ratio (pitfall 4).
        return MasonryGridView.count(
          padding: padding.add(
            const .only(bottom: HiwiskiMetrics.fabClearance),
          ),
          crossAxisCount: columns,
          crossAxisSpacing: HiwiskiMetrics.space12,
          mainAxisSpacing: HiwiskiMetrics.space12,
          itemCount: widget.lists.length,
          itemBuilder: (context, index) {
            final summary = widget.lists[index];
            final card = _ListCard(summary: summary);
            final onMove = widget.onMove;
            if (onMove == null) return card;
            return _MovableCard(
              id: summary.list.id,
              width: cardWidth,
              onDragUpdate: (pointer) => _autoScroll.update(context, pointer),
              onDragDone: _autoScroll.stop,
              onDrop: (id) => onMove(id, summary.list.id),
              child: card,
            );
          },
        );
      },
    );
  }
}

/// A list card that can be picked up — after a long press on touch, at once with the
/// mouse — and that takes another dropped on it: the dropped one takes its place.
class _MovableCard extends StatelessWidget {
  const _MovableCard({
    required this.id,
    required this.width,
    required this.onDragUpdate,
    required this.onDragDone,
    required this.onDrop,
    required this.child,
    this.accepts,
  });

  final String id;

  /// Which dropped lists this card takes; without it, any other one.
  final bool Function(String id)? accepts;

  /// The card's width — the one held under the finger keeps it.
  final double width;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragDone;
  final ValueChanged<String> onDrop;
  final Widget child;

  @override
  Widget build(BuildContext context) => DragTarget<String>(
    onWillAcceptWithDetails: (details) =>
        details.data != id && (accepts?.call(details.data) ?? true),
    onAcceptWithDetails: (details) => onDrop(details.data),
    builder: (context, candidates, _) => ItemDraggable<String>(
      data: id,
      feedback: Material(
        type: .transparency,
        child: SizedBox(
          width: width,
          child: Opacity(opacity: 0.9, child: child),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: child),
      onDragStarted: () {},
      onDragUpdate: (details) => onDragUpdate(details.globalPosition),
      onDragDone: onDragDone,
      child: DecoratedBox(
        // Where the card would land: framed while one is held over it.
        position: .foreground,
        decoration: BoxDecoration(
          borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
          border: candidates.isEmpty
              ? null
              : .fromBorderSide(
                  BorderSide(
                    color: context.scheme.primary,
                    width: HiwiskiMetrics.strokeBold,
                  ),
                ),
        ),
        child: child,
      ),
    ),
  );
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.summary});

  final TodoListSummary summary;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = context.scheme;

    // Icon tile 40×40, title 17/600, count line, progress bar 4, tag chips.
    final shape = RoundedRectangleBorder(
      side: BorderSide(color: scheme.outlineVariant),
      borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
    );
    // No clip: the content keeps its padding, and the ripple follows the shape —
    // a clip per card was a layer of its own in every frame of a scroll.
    return Material(
      color: scheme.surfaceContainerLow,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: () => TodoListRoute(listId: summary.list.id).go(context),
        child: Padding(
          padding: const .symmetric(
            horizontal: HiwiskiMetrics.space16,
            vertical: HiwiskiMetrics.space14,
          ),
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              Row(
                spacing: HiwiskiMetrics.space12,
                children: [
                  ListKindTile(kind: summary.list.kind),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        // Title with the mono number next to it.
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: summary.list.name),
                              if (summary.list.entityKey case final key?)
                                TextSpan(
                                  text: '  $key',
                                  style: context.tokens.text.entityKey,
                                ),
                            ],
                          ),
                          overflow: .ellipsis,
                          style: context.tokens.text.cardTitle,
                        ),
                        Text(
                          l.todoCounts(summary.open, summary.done),
                          style: context.texts.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HiwiskiMetrics.space10),
              ThinProgress(value: summary.progress),
              if (summary.list.tags.isNotEmpty) ...[
                const SizedBox(height: HiwiskiMetrics.space10),
                TagChips(raw: summary.list.tags),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The view menu in the header, as in the calendar: the three ways to show the lists.
class _ViewMenu extends ConsumerWidget {
  const _ViewMenu({required this.mode});

  final TodoViewMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final modes = {
      TodoViewMode.together: (l.todoViewTogether, HiwiskiSymbols.dashboard),
      TodoViewMode.byKind: (l.todoViewByKind, HiwiskiSymbols.category),
      TodoViewMode.sidebar: (l.todoViewSidebar, HiwiskiSymbols.viewList),
    };
    final (label, icon) = modes[mode]!;
    return MenuAnchor(
      menuChildren: [
        Padding(
          padding: const .fromLTRB(
            HiwiskiMetrics.space12,
            HiwiskiMetrics.space8,
            HiwiskiMetrics.space12,
            HiwiskiMetrics.space4,
          ),
          child: Text(
            l.todoViewSection,
            style: context.tokens.text.sectionLabel,
          ),
        ),
        for (final MapEntry(key: entry, value: (text, _)) in modes.entries)
          MenuItemButton(
            key: TodoKeys.overviewView(entry.name),
            leadingIcon: Icon(
              entry == mode
                  ? HiwiskiSymbols.radioButtonChecked
                  : HiwiskiSymbols.radioButtonUnchecked,
            ),
            onPressed: () =>
                ref.read(todoOverviewViewModelProvider.notifier).setMode(entry),
            child: Text(text),
          ),
      ],
      builder: (context, anchor, _) {
        void toggle() => anchor.isOpen ? anchor.close() : anchor.open();
        // On the phone the symbol alone, as in the calendar.
        if (Breakpoint.of(context).isCompact) {
          return IconButton(
            key: TodoKeys.overviewViewMenu,
            icon: Icon(icon),
            tooltip: label,
            onPressed: toggle,
          );
        }
        return ActionChip(
          key: TodoKeys.overviewViewMenu,
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

/// One titled group per kind, each a grid of cards; a card moves within its group.
class _KindGroups extends StatefulWidget {
  const _KindGroups({
    required this.groups,
    required this.padding,
    required this.onMove,
  });

  final List<KindGroup> groups;
  final EdgeInsets padding;
  final void Function(String id, String targetId)? onMove;

  @override
  State<_KindGroups> createState() => _KindGroupsState();
}

class _KindGroupsState extends State<_KindGroups> {
  final _autoScroll = DragAutoScroll();

  @override
  void dispose() {
    _autoScroll.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final padding = widget.padding;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - padding.horizontal;
        final columns = (width / HiwiskiMetrics.gridMinTodoList).floor().clamp(
          1,
          6,
        );
        final cardWidth =
            (width - (columns - 1) * HiwiskiMetrics.space12) / columns;
        return CustomScrollView(
          slivers: [
            for (final (index, group) in widget.groups.indexed) ...[
              SliverPadding(
                padding: padding.copyWith(
                  top: index == 0 ? padding.top : HiwiskiMetrics.space24,
                  bottom: HiwiskiMetrics.space12,
                ),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    spacing: HiwiskiMetrics.space8,
                    children: [
                      Text(switch (group.kind) {
                        ListKinds.shopping => l.todoKindShopping,
                        ListKinds.kanban => l.todoKindKanban,
                        _ => l.todoKindStandard,
                      }, style: context.texts.titleMedium),
                      Text(
                        '${group.lists.length}',
                        style: context.tokens.text.entityKey,
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: padding.copyWith(top: 0, bottom: 0),
                sliver: SliverMasonryGrid.count(
                  crossAxisCount: columns,
                  crossAxisSpacing: HiwiskiMetrics.space12,
                  mainAxisSpacing: HiwiskiMetrics.space12,
                  childCount: group.lists.length,
                  itemBuilder: (context, i) {
                    final summary = group.lists[i];
                    final card = _ListCard(summary: summary);
                    final onMove = widget.onMove;
                    if (onMove == null) return card;
                    final ids = {for (final s in group.lists) s.list.id};
                    return _MovableCard(
                      id: summary.list.id,
                      width: cardWidth,
                      accepts: ids.contains,
                      onDragUpdate: (pointer) =>
                          _autoScroll.update(context, pointer),
                      onDragDone: _autoScroll.stop,
                      onDrop: (id) => onMove(id, summary.list.id),
                      child: card,
                    );
                  },
                ),
              ),
            ],
            const SliverToBoxAdapter(
              child: SizedBox(height: HiwiskiMetrics.fabClearance),
            ),
          ],
        );
      },
    );
  }
}

/// The lists as rows, like the wiki's pages: the kind's tile, name and counts. A long
/// press sorts them.
class _ListRows extends StatelessWidget {
  const _ListRows({
    required this.lists,
    required this.selectedId,
    required this.padding,
    required this.onOpen,
    required this.onMove,
  });

  final List<TodoListSummary> lists;

  /// The list open next to the rows; `null` on the phone.
  final String? selectedId;
  final EdgeInsets padding;
  final ValueChanged<String> onOpen;
  final void Function(String id, String targetId)? onMove;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final onMove = this.onMove;
    return ReorderableListView(
      padding: padding,
      buildDefaultDragHandles: false,
      // The list moved takes the place of the one that stood at its new index.
      onReorderItem: (from, to) {
        if (onMove != null && from != to) {
          onMove(lists[from].list.id, lists[to].list.id);
        }
      },
      footer: Padding(
        padding: const .only(top: HiwiskiMetrics.space8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(HiwiskiSymbols.add),
            label: Text(l.todoNewList),
            onPressed: () => showNewListSheet(context),
          ),
        ),
      ),
      children: [
        for (final (index, summary) in lists.indexed)
          _MovableRow(
            key: ValueKey(summary.list.id),
            index: index,
            enabled: onMove != null,
            child: _ListRow(
              summary: summary,
              selected: summary.list.id == selectedId,
              onTap: () => onOpen(summary.list.id),
            ),
          ),
      ],
    );
  }
}

class _MovableRow extends StatelessWidget {
  const _MovableRow({
    super.key,
    required this.index,
    required this.enabled,
    required this.child,
  });

  final int index;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => enabled
      ? ReorderableDelayedDragStartListener(index: index, child: child)
      : child;
}

/// A list as a row: on `sec` while it is the one open.
class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.summary,
    required this.selected,
    required this.onTap,
  });

  final TodoListSummary summary;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = context.scheme;
    return Padding(
      padding: const .symmetric(vertical: HiwiskiMetrics.hairline),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
        child: InkWell(
          key: TodoKeys.overviewRow(summary.list.id),
          borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
          onTap: onTap,
          child: Padding(
            padding: const .symmetric(
              horizontal: HiwiskiMetrics.space8,
              vertical: HiwiskiMetrics.space6,
            ),
            child: Row(
              spacing: HiwiskiMetrics.space12,
              children: [
                ListKindTile(kind: summary.list.kind),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: summary.list.name),
                            if (summary.list.entityKey case final key?)
                              TextSpan(
                                text: '  $key',
                                style: context.tokens.text.entityKey,
                              ),
                          ],
                        ),
                        overflow: .ellipsis,
                        style: context.texts.bodyLarge?.copyWith(
                          fontWeight: selected ? .w600 : .w400,
                          color: selected ? scheme.onSecondaryContainer : null,
                        ),
                      ),
                      Text(
                        l.todoCounts(summary.open, summary.done),
                        style: context.texts.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wide: the rows on the left, as wide as the wiki's tree, the chosen list open next
/// to them — the same screen it has of its own. Like the wiki's tree the rows can be
/// put away (`left_panel_close/open`), and the list takes the whole width.
class _SidebarLayout extends ConsumerStatefulWidget {
  const _SidebarLayout({required this.state, required this.onMove});

  final TodoOverviewState state;
  final void Function(String id, String targetId)? onMove;

  @override
  ConsumerState<_SidebarLayout> createState() => _SidebarLayoutState();
}

class _SidebarLayoutState extends ConsumerState<_SidebarLayout> {
  /// Whether the rows show. This screen's matter, not the family's — as the wiki's
  /// tree.
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final state = widget.state;
    final selected = state.selectedId;
    final showRows = _open
        ? null
        : IconButton(
            key: TodoKeys.overviewRowsShow,
            icon: const Icon(HiwiskiSymbols.leftPanelOpen),
            tooltip: l.todoListsShow,
            onPressed: () => setState(() => _open = true),
          );
    return Row(
      crossAxisAlignment: .stretch,
      children: [
        if (_open) ...[
          SizedBox(
            width: HiwiskiMetrics.treeWidth + HiwiskiMetrics.space32,
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                // The button first: put away, the rows leave the one that brings
                // them back at the same place, left of the list's title.
                Padding(
                  padding: const .only(
                    left: PanelReopen.inset,
                    right: HiwiskiMetrics.space8,
                  ),
                  child: Row(
                    spacing: HiwiskiMetrics.space4,
                    children: [
                      IconButton(
                        key: TodoKeys.overviewRowsHide,
                        icon: const Icon(HiwiskiSymbols.leftPanelClose),
                        tooltip: l.todoListsHide,
                        onPressed: () => setState(() => _open = false),
                      ),
                      Expanded(
                        child: Text(
                          l.todoListsLabel,
                          style: context.texts.labelLarge?.copyWith(
                            color: context.scheme.onSurfaceVariant,
                            fontWeight: .w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _ListRows(
                    lists: state.lists,
                    selectedId: selected,
                    padding: const .only(
                      left: HiwiskiMetrics.space32 - HiwiskiMetrics.space4,
                      right: HiwiskiMetrics.space8,
                      bottom: HiwiskiMetrics.space8,
                    ),
                    onOpen: (id) => ref
                        .read(todoOverviewViewModelProvider.notifier)
                        .select(id),
                    onMove: widget.onMove,
                  ),
                ),
              ],
            ),
          ),
          VerticalDivider(
            width: HiwiskiMetrics.hairline,
            color: context.tokens.divider,
          ),
        ],
        Expanded(
          child: selected == null
              ? PanelReopenCorner(
                  button: showRows,
                  inset: PanelReopen.inset,
                  child: const SizedBox.shrink(),
                )
              // Inside this page: its header keeps the one avatar, not a second.
              : PanelReopen(
                  button: showRows,
                  child: EmbeddedPage(
                    child: TodoListScreen(
                      key: ValueKey(selected),
                      listId: selected,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
