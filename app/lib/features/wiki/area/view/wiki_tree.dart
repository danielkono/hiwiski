import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_accents.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/drag_auto_scroll.dart';
import '../../../../core/ui/item_draggable.dart';
import '../../../../domain/wiki/page_moves.dart';
import '../../../../domain/wiki/wiki_models.dart';
import '../../../../domain/wiki/wiki_page.dart';
import '../../page/view/page_kind.dart';

/// The page tree: **arbitrarily deep, indent 22 px per level**.
///
/// Expand arrow, lock for restricted sharing, active page on `sec`. A row looks like a
/// list's in the task overview: the kind's tile, the title, and below it how many
/// subpages — or, in a recipe branch, recipes — lie under it. Each node has a
/// "+": it opens the dialog that asks for title and kind — page or recipe collection,
/// under a recipe branch recipe or folder. A recipe branch's "+" is a menu that also
/// offers the recipe import, so a recipe from the web lands where it belongs.
///
/// **Pages move by drag and drop** — on touch after a long press, with the mouse at
/// once: dropped on the upper third of a row the page goes before it, on its middle
/// inside it as its last subpage, on its lower third after it. A line or a frame shows
/// where it lands; a collapsed page held over opens. Only pages the member may write
/// move ([movable]).
class WikiTree extends StatefulWidget {
  const WikiTree({
    super.key,
    required this.nodes,
    required this.groupShared,
    required this.selectedId,
    required this.onSelect,
    this.onCreate,
    this.onImport,
    this.onDrop,
    this.movable = const {},
    this.expanded = const {},
    this.onExpandedChanged = _ignore,
  });

  static void _ignore(Set<String> _) {}

  /// The nodes expanded when the tree is built — what it held last time.
  final Set<String> expanded;

  /// The expanded nodes after a change, to keep for the next time.
  final ValueChanged<Set<String>> onExpandedChanged;

  final List<WikiNode> nodes;

  /// For a root: whether a group sees it; missing while not known.
  final Map<String, bool> groupShared;
  final String? selectedId;
  final ValueChanged<WikiPage> onSelect;

  /// Something new under `parentId` — `null` means root. The dialog asks what.
  final ValueChanged<String?>? onCreate;

  /// A recipe from an address, into this recipe branch.
  final ValueChanged<String>? onImport;

  /// A page dropped on a row; `null` where nothing moves.
  final void Function(String id, String targetId, DropZone zone)? onDrop;

  /// The pages that may be picked up and dropped into.
  final Set<String> movable;

  /// "Indent 22 px per level."
  static const indent = HiwiskiMetrics.wikiIndent;

  @override
  State<WikiTree> createState() => _WikiTreeState();
}

class _WikiTreeState extends State<WikiTree> {
  /// Which nodes are expanded — starting from what the tree held last time, and
  /// handed back on every change ([WikiTree.onExpandedChanged]): leaving the wiki and
  /// coming back keeps the tree as it was.
  late final _expanded = <String>{...widget.expanded};

  @override
  void initState() {
    super.initState();
    if (_revealSelected(widget.nodes, const [])) _announceLater();
  }

  @override
  void didUpdateWidget(WikiTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Changed from outside — "Expand all", "Collapse all" —, not the echo of what
    // the tree handed on itself.
    if (!setEquals(oldWidget.expanded, widget.expanded) &&
        !setEquals(widget.expanded, _expanded)) {
      _expanded
        ..clear()
        ..addAll(widget.expanded);
    }
    if (oldWidget.selectedId != widget.selectedId &&
        _revealSelected(widget.nodes, const [])) {
      _announceLater();
    }
  }

  /// Hands the expanded nodes on — after the frame where it happens during a build.
  void _announce() => widget.onExpandedChanged({..._expanded});

  void _announceLater() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _announce();
  });

  /// Expands or collapses [id] and says so.
  void _setOpen(String id, {required bool open}) {
    setState(() => open ? _expanded.add(id) : _expanded.remove(id));
    _announce();
  }

  /// Expands the path to the selected page — otherwise it would be there but invisible —
  /// and the page itself: whoever opens a page with subpages wants to see them.
  bool _revealSelected(List<WikiNode> nodes, List<String> trail) {
    for (final node in nodes) {
      if (node.page.id == widget.selectedId) {
        _expanded.addAll([
          ...trail,
          if (node.children.isNotEmpty) node.page.id,
        ]);
        return true;
      }
      if (_revealSelected(node.children, [...trail, node.page.id])) return true;
    }
    return false;
  }

  /// The rows as shown: every node whose ancestors are all expanded, with its depth.
  List<_Shown> _visible(List<WikiNode> nodes, int depth) => [
    for (final node in nodes) ...[
      _Shown(node, depth),
      if (_expanded.contains(node.page.id))
        ..._visible(node.children, depth + 1),
    ],
  ];

  final _autoScroll = DragAutoScroll();

  /// The page being dragged and the pages below it — no drop target for it.
  Set<String> _below = const {};

  /// Where it would land.
  String? _targetId;
  DropZone? _zone;

  /// Opens a collapsed page held over for a moment.
  Timer? _expandTimer;

  @override
  void dispose() {
    _autoScroll.stop();
    _expandTimer?.cancel();
    super.dispose();
  }

  static Set<String> _subtree(WikiNode node) => {
    node.page.id,
    for (final child in node.children) ..._subtree(child),
  };

  void _startDrag(WikiNode node) => setState(() => _below = _subtree(node));

  void _endDrag() {
    _autoScroll.stop();
    _expandTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _below = const {};
      _targetId = null;
      _zone = null;
    });
  }

  /// The zone of a row under the pointer: its upper third, middle or lower third. The
  /// middle only where something may go inside.
  DropZone _zoneAt(BuildContext row, Offset pointer, String targetId) {
    final box = row.findRenderObject();
    if (box is! RenderBox) return .after;
    final y = box.globalToLocal(pointer).dy / box.size.height;
    final inside = widget.movable.contains(targetId);
    return switch (y) {
      < 1 / 3 => .before,
      > 2 / 3 => .after,
      _ when inside => .inside,
      _ when y < 0.5 => .before,
      _ => .after,
    };
  }

  void _hover(BuildContext row, WikiNode node, Offset pointer) {
    final zone = _zoneAt(row, pointer, node.page.id);
    if (zone == .inside &&
        node.children.isNotEmpty &&
        !_expanded.contains(node.page.id) &&
        (_targetId != node.page.id || _zone != .inside)) {
      _expandTimer?.cancel();
      _expandTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted) _setOpen(node.page.id, open: true);
      });
    } else if (zone != .inside) {
      _expandTimer?.cancel();
    }
    if (_targetId != node.page.id || _zone != zone) {
      setState(() {
        _targetId = node.page.id;
        _zone = zone;
      });
    }
  }

  void _leave(String targetId) {
    if (_targetId != targetId) return;
    _expandTimer?.cancel();
    setState(() {
      _targetId = null;
      _zone = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible(widget.nodes, 0);
    final onDrop = widget.onDrop;
    return ListView(
      padding: const .symmetric(vertical: HiwiskiMetrics.space8),
      children: [
        for (final _Shown(:node, :depth) in rows)
          Builder(
            key: ValueKey(node.page.id),
            builder: (rowContext) {
              final id = node.page.id;
              final row = _Row(
                node: node,
                depth: depth,
                open: _expanded.contains(id),
                selected: id == widget.selectedId,
                groupShared: widget.groupShared[id],
                onToggle: () => _setOpen(id, open: !_expanded.contains(id)),
                onSelect: () => widget.onSelect(node.page),
                onCreate: widget.onCreate,
                onImport: widget.onImport,
              );
              if (onDrop == null) return row;
              final marked = _DropMark(
                depth: depth,
                zone: _targetId == id ? _zone : null,
                child: row,
              );
              final target = DragTarget<String>(
                onWillAcceptWithDetails: (details) => !_below.contains(id),
                onMove: (details) => _hover(rowContext, node, details.offset),
                onLeave: (_) => _leave(id),
                onAcceptWithDetails: (details) {
                  final zone = _zoneAt(rowContext, details.offset, id);
                  _endDrag();
                  // Dropped inside: the page opens, so the moved page shows
                  // where it landed.
                  if (zone == .inside) _setOpen(id, open: true);
                  onDrop(details.data, id, zone);
                },
                builder: (_, _, _) => marked,
              );
              if (!widget.movable.contains(id)) return target;
              return ItemDraggable<String>(
                data: id,
                feedback: _DragFeedback(title: node.page.title),
                childWhenDragging: Opacity(opacity: 0.4, child: target),
                onDragStarted: () => _startDrag(node),
                onDragUpdate: (details) =>
                    _autoScroll.update(rowContext, details.globalPosition),
                onDragDone: _endDrag,
                child: target,
              );
            },
          ),
        // A new page at the top level is the screen's floating button, where a new
        // list and a new event are.
      ],
    );
  }
}

/// A shown row of the tree: its node and how deep it sits.
class const _Shown(final WikiNode node, final int depth);

/// Where a dragged page would land on this row: a line above or below it, at the
/// row's depth, or a frame around it for "inside".
class _DropMark extends StatelessWidget {
  const _DropMark({
    required this.depth,
    required this.zone,
    required this.child,
  });

  final int depth;
  final DropZone? zone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = context.scheme.primary;
    final zone = this.zone;
    if (zone == null) return child;
    final line = Positioned(
      left: HiwiskiMetrics.space4 + depth * WikiTree.indent,
      right: 0,
      height: HiwiskiMetrics.strokeBold,
      top: zone == .before ? 0 : null,
      bottom: zone == .after ? 0 : null,
      child: ColoredBox(color: color),
    );
    return Stack(
      children: [
        if (zone == .inside)
          DecoratedBox(
            position: .foreground,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
              border: .fromBorderSide(
                BorderSide(color: color, width: HiwiskiMetrics.strokeBold),
              ),
            ),
            child: child,
          )
        else ...[
          child,
          line,
        ],
      ],
    );
  }
}

/// What follows the pointer: the page's title on a card.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Material(
    elevation: HiwiskiMetrics.elevationDrag,
    color: context.scheme.surfaceContainerHigh,
    borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
    child: Padding(
      padding: const .symmetric(
        horizontal: HiwiskiMetrics.space16,
        vertical: HiwiskiMetrics.space10,
      ),
      child: Text(title, style: context.texts.bodyLarge),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.node,
    required this.depth,
    required this.open,
    required this.selected,
    required this.groupShared,
    required this.onToggle,
    required this.onSelect,
    this.onCreate,
    this.onImport,
  });

  final WikiNode node;

  /// Whether a group sees this root; `null` while not known.
  final bool? groupShared;
  final int depth;
  final bool open;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onSelect;
  final ValueChanged<String?>? onCreate;
  final ValueChanged<String>? onImport;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final hasChildren = node.children.isNotEmpty;
    final scheme = context.scheme;
    final root = depth == 0;

    // As a list's row in the task overview: the kind's tile, the title, below it what
    // lies under the page. Active page on `sec`, roots bold.
    final count = switch (node) {
      _ when node.isRecipe => null,
      _ when node.isRecipeBranch && node.recipeCount > 0 => l.wikiRecipeCount(
        node.recipeCount,
      ),
      _ when node.subpageCount > 0 => l.wikiSubpageCount(node.subpageCount),
      _ => null,
    };
    return Padding(
      padding: const .symmetric(vertical: HiwiskiMetrics.hairline),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
        child: InkWell(
          onTap: onSelect,
          borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: HiwiskiMetrics.minTapTarget,
            ),
            child: Padding(
              padding: .only(
                left: depth * WikiTree.indent,
                right: HiwiskiMetrics.space4,
              ),
              child: Row(
                children: [
                  // As wide as a finger needs: the arrow alone was 24 wide, and a
                  // tap beside it opened the page instead.
                  SizedBox(
                    width: HiwiskiMetrics.minTapTarget,
                    child: hasChildren
                        ? IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: HiwiskiMetrics.icon20,
                            color: scheme.onSurfaceVariant,
                            tooltip: open
                                ? l.wikiSubpagesHide
                                : l.wikiSubpagesShow,
                            icon: Icon(
                              open
                                  ? HiwiskiSymbols.expandMore
                                  : HiwiskiSymbols.chevronRight,
                            ),
                            onPressed: onToggle,
                          )
                        : null,
                  ),
                  Padding(
                    padding: const .symmetric(vertical: HiwiskiMetrics.space6),
                    child: _PageTile(node: node),
                  ),
                  const SizedBox(width: HiwiskiMetrics.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      mainAxisSize: .min,
                      children: [
                        Text(
                          node.page.title,
                          overflow: .ellipsis,
                          style: context.texts.bodyLarge?.copyWith(
                            fontWeight: root || selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected
                                ? scheme.onSecondaryContainer
                                : null,
                          ),
                        ),
                        if (count != null)
                          Text(
                            count,
                            overflow: .ellipsis,
                            style: context.texts.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // The recipe symbol is in the tile now; the access hint stays.
                  if (root && !node.isRecipeBranch)
                    _AccessHint(groupShared: groupShared),
                  if ((onCreate, onImport)
                      case (final onCreate?, final onImport?)
                      when node.isRecipeBranch)
                    MenuAnchor(
                      menuChildren: [
                        MenuItemButton(
                          leadingIcon: const Icon(HiwiskiSymbols.add),
                          onPressed: () => onCreate(node.page.id),
                          child: Text(l.wikiNewEllipsis),
                        ),
                        MenuItemButton(
                          leadingIcon: const Icon(HiwiskiSymbols.download),
                          onPressed: () => onImport(node.page.id),
                          child: Text(l.recipeImportAction),
                        ),
                      ],
                      builder: (context, anchor, _) => IconButton(
                        iconSize: HiwiskiMetrics.icon20,
                        color: scheme.onSurfaceVariant,
                        icon: const Icon(HiwiskiSymbols.add),
                        tooltip: l.wikiCreateIn(node.page.title),
                        onPressed: () =>
                            anchor.isOpen ? anchor.close() : anchor.open(),
                      ),
                    )
                  else if (onCreate case final onCreate?)
                    IconButton(
                      iconSize: HiwiskiMetrics.icon20,
                      color: scheme.onSurfaceVariant,
                      icon: const Icon(HiwiskiSymbols.add),
                      tooltip: l.wikiCreateIn(node.page.title),
                      onPressed: () => onCreate(node.page.id),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A page's tile, as a list's in the task overview: `description` on `pc` for a page,
/// `restaurant` on the recipe amber for a recipe or a recipe collection, `folder` for a
/// folder inside one.
class _PageTile extends StatelessWidget {
  const _PageTile({required this.node});

  final WikiNode node;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final recipes = node.isRecipeBranch;
    final amber = context.tokens.tag(TagToken.amber);
    const size = HiwiskiMetrics.tileSize;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: recipes ? amber.background : scheme.primaryContainer,
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusMenu)),
      ),
      child: Icon(
        // The kind says which (`PageKindView.treeIcon`).
        PageKindView.of(node.page).treeIcon(node),
        size: size * 0.55,
        color: recipes ? amber.foreground : scheme.onPrimaryContainer,
      ),
    );
  }
}

/// Who sees a root, at a glance: **group** if a group sees it, **lock** if only
/// individual people or only the owner do. Subpages inherit and therefore carry none.
///
/// The information comes from the same call as the share sheet; offline nothing shows
/// rather than a guessed lock.
class _AccessHint extends StatelessWidget {
  const _AccessHint({required this.groupShared});

  final bool? groupShared;

  @override
  Widget build(BuildContext context) {
    final shared = groupShared;
    if (shared == null) return const SizedBox.shrink();
    return Padding(
      padding: const .only(left: HiwiskiMetrics.space4),
      child: Icon(
        shared ? HiwiskiSymbols.group : HiwiskiSymbols.lock,
        size: HiwiskiMetrics.icon18,
        color: context.scheme.onSurfaceVariant,
      ),
    );
  }
}
