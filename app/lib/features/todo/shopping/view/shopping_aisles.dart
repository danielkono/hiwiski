import 'package:flutter/material.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/drag_auto_scroll.dart';
import '../../../../core/ui/item_draggable.dart';
import '../../../../core/ui/renamable_row.dart';
import '../../../../domain/catalog/catalog_product.dart';
import '../../../../domain/todo/todo_items.dart';
import '../../../../domain/todo/todo_models.dart';
import '../../view/aisle_ui.dart';
import '../../view/row_drop_slot.dart';
import '../../view/todo_keys.dart';

/// The shopping list's rows grouped by category, in the family's order.
///
/// **A row is dragged into another category** — with the mouse at once, by touch after
/// a long press. That writes the category into the catalog: from then on the product
/// lands there in every list. Holding a row changes nothing about the list: the
/// categories in it stay where they are, only the one under the finger lights up. One
/// target appears below them, **"Other category"**; held over it, the categories not in
/// the list open up beneath it, and dropping on one adds it to the list.
///
/// **Dropped on a row, it goes before or after it** — a line shows where. That sorts
/// the rows within a category, in the order one walks the shop; it is the list's own
/// order, kept in the rows' positions.
///
/// Near the edge of what is visible the list scrolls by itself, the faster the closer
/// the finger, so it works with one hand ([DragAutoScroll]).
class ShoppingAisles extends StatefulWidget {
  const ShoppingAisles({
    super.key,
    required this.items,
    required this.products,
    required this.aisles,
    required this.movable,
    required this.rowBuilder,
    required this.onAssignAisle,
    required this.onReposition,
    this.sliver = false,
    this.onRename,
  });

  final List<Todo> items;
  final List<CatalogProduct> products;
  final List<CatalogAisle> aisles;

  /// Whether rows may be dragged — whoever may write the list.
  final bool movable;

  final Widget Function(Todo todo) rowBuilder;

  /// Writes the product's category into the catalog — throws offline.
  final Future<void> Function(String productName, String? aisleId)
  onAssignAisle;

  /// Puts a row among [others] at [at] — the list's own order.
  final Future<void> Function(
    Todo item, {
    required List<Todo> others,
    required int at,
  })
  onReposition;

  /// As a sliver in its page's scroll view: a category is built when it comes into
  /// view, not all of them for the first frame.
  final bool sliver;

  /// A row's title, edited in place — `null` where it is not. Around the drag, which
  /// hands a hold that does not move on to it ([ItemDraggable]).
  final void Function(Todo todo, String title)? onRename;

  @override
  State<ShoppingAisles> createState() => _ShoppingAislesState();
}

class _ShoppingAislesState extends State<ShoppingAisles> {
  /// The row being held, if any.
  Todo? _dragging;

  /// Whether the held row has been over "Other category" — then the remaining
  /// categories stay open until it is let go, so the finger can move down to them.
  bool _othersOpen = false;

  /// Scrolls the list the rows sit in while a row is held near its edge.
  final _autoScroll = DragAutoScroll();

  /// Drops [todo] into [target], whose rows are [rows]: before or after [onRow] if it
  /// landed on one, otherwise at the end. Into another category it first writes the
  /// category into the catalog — online only; offline the row stays where it was.
  Future<void> _drop(
    Todo todo, {
    required CatalogAisle? target,
    required CatalogAisle? from,
    required List<Todo> rows,
    Todo? onRow,
    bool before = true,
  }) async {
    // Held before the network: navigated away while the category is written, the
    // widget may be gone, and the reposition was lost.
    final reposition = widget.onReposition;
    if (target?.id != from?.id) {
      final moved = await runCatalogChange(
        context,
        () => widget.onAssignAisle(
          catalogNameFor(todo.title, todo.productId, widget.products),
          target?.id,
        ),
      );
      if (!moved) return;
    } else if (onRow == null) {
      // On its own category's heading: nothing to do.
      return;
    }
    final (:others, :at) = dropPlace(
      todo,
      rows: rows,
      onRow: onRow,
      before: before,
    );
    await reposition(todo, others: others, at: at);
  }

  void _startDrag(Todo todo) => setState(() {
    _dragging = todo;
    _othersOpen = false;
  });

  void _endDrag() {
    _autoScroll.stop();
    setState(() {
      _dragging = null;
      _othersOpen = false;
    });
  }

  @override
  void dispose() {
    _autoScroll.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = groupByAisle(
      widget.items,
      title: (todo) => todo.title,
      productId: (todo) => todo.productId,
      products: widget.products,
      aisles: widget.aisles,
    );
    final byAisle = {for (final (aisle, rows) in groups) aisle?.id: rows};
    final shown = [for (final (aisle, _) in groups) aisle];

    // What "Other category" offers: every category not in the list, in the family's
    // order, and "Other" last unless it is there already.
    final shownIds = {for (final aisle in shown) aisle?.id};
    final remaining = [
      for (final aisle in offeredAisles(widget.aisles))
        if (!shownIds.contains(aisle.id)) aisle,
      // The ids are `String?`; `null` is "Other".
      // ignore: many_lints/avoid_collection_methods_with_unrelated_types
      if (!shownIds.contains(null)) null,
    ];

    CatalogAisle? fromOf(Todo todo) => groups
        .where((group) => group.$2.any((row) => row.id == todo.id))
        .firstOrNull
        ?.$1;

    ValueChanged<String>? renamer(Todo todo) => switch (widget.onRename) {
      final rename? => (title) => rename(todo, title),
      null => null,
    };

    Widget group(CatalogAisle? aisle) {
      final rows = byAisle[aisle?.id] ?? const <Todo>[];
      return _Group(
        key: TodoKeys.shoppingAisle(aisle?.id ?? _other),
        aisle: aisle,
        onDrop: (todo) =>
            _drop(todo, target: aisle, from: fromOf(todo), rows: rows),
        children: [
          for (final todo in rows)
            if (widget.movable)
              RowDropSlot(
                key: TodoKeys.shoppingRow(todo.id),
                row: todo,
                onDrop: (dragged, {required before}) => _drop(
                  dragged,
                  target: aisle,
                  from: fromOf(dragged),
                  rows: rows,
                  onRow: todo,
                  before: before,
                ),
                child: RenamableRow(
                  onRenamed: renamer(todo),
                  child: _DraggableRow(owner: this, todo: todo),
                ),
              )
            else
              RenamableRow(
                onRenamed: renamer(todo),
                child: widget.rowBuilder(todo),
              ),
        ],
      );
    }

    final children = [
      for (final aisle in shown) group(aisle),
      // Below the list, so nothing above it moves when it appears.
      if (_dragging != null && remaining.isNotEmpty) ...[
        _OtherAisles(
          open: _othersOpen,
          onHover: () {
            if (!_othersOpen) setState(() => _othersOpen = true);
          },
        ),
        if (_othersOpen)
          for (final aisle in remaining) group(aisle),
      ],
    ];
    return widget.sliver
        ? SliverList.list(children: children)
        : Column(crossAxisAlignment: .stretch, children: children);
  }
}

/// A row that can be picked up and dropped on another category.
class _DraggableRow extends StatelessWidget {
  const _DraggableRow({required this.owner, required this.todo});

  final _ShoppingAislesState owner;
  final Todo todo;

  @override
  Widget build(BuildContext context) {
    final row = owner.widget.rowBuilder(todo);
    final feedback = SizedBox(
      width: HiwiskiMetrics.dragFeedbackWidth,
      child: Material(
        elevation: HiwiskiMetrics.elevationDrag,
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusMenu)),
        child: row,
      ),
    );
    final placeholder = Opacity(opacity: 0.35, child: row);

    return ItemDraggable<Todo>(
      data: todo,
      feedback: feedback,
      childWhenDragging: placeholder,
      onDragStarted: () => owner._startDrag(todo),
      onDragUpdate: (details) =>
          owner._autoScroll.update(owner.context, details.globalPosition),
      onDragDone: owner._endDrag,
      child: row,
    );
  }
}

const _other = 'other';

/// One category: its heading in `pri`, its rows — and a drop target for rows from
/// elsewhere, lit up while a row is held over it.
class _Group extends StatelessWidget {
  const _Group({
    super.key,
    required this.aisle,
    required this.onDrop,
    required this.children,
  });

  final CatalogAisle? aisle;
  final void Function(Todo todo) onDrop;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return DragTarget<Todo>(
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidates, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: candidates.isNotEmpty ? context.scheme.surfaceContainer : null,
          borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [_Heading(aisleLabel(l, aisle)), ...children],
        ),
      ),
    );
  }
}

/// "Other category" below the list while a row is held. Held over it, the categories
/// not in the list open beneath it.
class _OtherAisles extends StatelessWidget {
  const _OtherAisles({required this.open, required this.onHover});

  final bool open;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return DragTarget<Todo>(
      key: TodoKeys.shoppingOtherAisles,
      // Not a place to drop: only the way to the categories beneath it.
      onWillAcceptWithDetails: (_) {
        onHover();
        return false;
      },
      builder: (context, _, _) => Padding(
        padding: const .only(top: HiwiskiMetrics.space8),
        child: Row(
          children: [
            Expanded(child: _Heading(l.shoppingOtherAisles)),
            Icon(
              open ? HiwiskiSymbols.expandLess : HiwiskiSymbols.expandMore,
              size: HiwiskiMetrics.icon18,
              color: context.scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .fromLTRB(
      HiwiskiMetrics.space4,
      HiwiskiMetrics.space12,
      HiwiskiMetrics.space4,
      HiwiskiMetrics.space4,
    ),
    child: Text(text, style: context.tokens.text.sectionLabel),
  );
}
