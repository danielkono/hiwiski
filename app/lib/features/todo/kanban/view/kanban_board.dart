import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../components/tags/view/tag_widgets.dart';
import '../../../../core/ui/new_row_reveal.dart';
import '../../../../core/api/generated/export.dart';
import '../../../../core/common/wire.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/item_navigation.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/color_tokens.dart';
import '../../../../core/ui/drag_auto_scroll.dart';
import '../../../../core/ui/item_draggable.dart';
import '../../../../core/ui/renamable_row.dart';
import '../../../../core/ui/renamable_title.dart';
import '../../../../domain/tags/tag.dart';
import '../../../../domain/todo/kanban.dart';
import '../../../../domain/todo/todo_items.dart';
import '../../../../core/ui/delete_hold_button.dart';
import '../../view/removable_row.dart';
import '../../view/todo_keys.dart';
import '../../view/todo_meta.dart';
import '../kanban_view_model.dart';

/// A column's width on the wide board.

/// The gap between two columns.
const _columnGap = HiwiskiMetrics.space12;

/// How much of the screen one column takes on the phone — the rest shows the edge of
/// its neighbours, so one sees that there is more, and roughly what.
const _pageFraction = 0.86;

/// The board of a Kanban list.
///
/// **Wide enough for two columns**: the columns side by side, scrolling sideways when
/// they do not fit. **On the phone** one column at a time, as pages swiped sideways,
/// slightly zoomed out. Cards move by drag and drop in both — with the mouse at once,
/// by touch after a long press.
class KanbanBoard extends ConsumerStatefulWidget {
  const KanbanBoard({
    super.key,
    required this.list,
    required this.columns,
    required this.cards,
    required this.writable,
    required this.mayMove,
    this.members = const {},
    this.padding = EdgeInsets.zero,
    this.preview = false,
  });

  final TodoList list;
  final List<KanbanColumn> columns;
  final List<Todo> cards;

  /// *write*: adds cards and reorders them within a column.
  final bool writable;

  /// Whether this card may change its column — *check off* is enough for that,
  /// and so is being assigned to it.
  final bool Function(Todo card) mayMove;

  /// The family by id, for the names in a card's meta line.
  final Map<String, Member> members;

  final EdgeInsets padding;

  /// In a link's preview: cards move, but none is added, and a tap opens the card's
  /// preview instead of its page.
  final bool preview;

  @override
  ConsumerState<KanbanBoard> createState() => _KanbanBoardState();
}

/// Where a dragged card would land: before the card at [index] of [columnId].
typedef _Slot = ({String columnId, int index});

class _KanbanBoardState extends ConsumerState<KanbanBoard> {
  final _cardKeys = <String, GlobalKey>{};
  final _boardKey = GlobalKey();
  final _horizontal = ScrollController();
  PageController? _pages;
  int _page = 0;

  /// The card being dragged and where it would land — the gap opens there.
  Todo? _dragging;
  _Slot? _slot;

  /// Moves the board while a card is held at its edge.
  Timer? _edgeTimer;
  int _edgeDirection = 0;

  /// Scrolls a column while a card is held at its top or bottom — otherwise a card
  /// could not be taken further down than the column shows.
  final _columnScroll = DragAutoScroll();

  /// Follows a card just added to the end of its column, or brought back by "Undo".
  final _newCard = NewRowReveal();

  @override
  void dispose() {
    _columnScroll.stop();
    _edgeTimer?.cancel();
    _horizontal.dispose();
    _pages?.dispose();
    super.dispose();
  }

  GlobalKey _keyOf(Todo card) =>
      _cardKeys.putIfAbsent(card.id, () => GlobalKey());

  /// The index among [cards] (without the dragged one) the pointer at [globalY] points
  /// before.
  int _indexAt(List<Todo> cards, double globalY) => slotIndex([
    for (final card in cards)
      if (card.id != _dragging?.id)
        switch (_cardKeys[card.id]?.currentContext?.findRenderObject()) {
          final RenderBox box when box.attached =>
            box.localToGlobal(Offset(0, box.size.height / 2)).dy,
          _ => null,
        },
  ], globalY);

  void _hover(KanbanColumn column, List<Todo> cards, Offset pointer) {
    final slot = (columnId: column.id, index: _indexAt(cards, pointer.dy));
    if (slot != _slot) setState(() => _slot = slot);
    // Any card of the column sits inside its list — the scrollable to move.
    final inside = cards
        .map((card) => _cardKeys[card.id]?.currentContext)
        .nonNulls
        .firstOrNull;
    if (inside == null) {
      _columnScroll.stop();
    } else {
      _columnScroll.update(inside, pointer);
    }
  }

  void _leave(KanbanColumn column) {
    _columnScroll.stop();
    if (_slot?.columnId == column.id) setState(() => _slot = null);
  }

  Future<void> _drop(
    KanbanColumn column,
    List<Todo> cards,
    Todo card,
    Offset pointer,
  ) async {
    final index = _indexAt(cards, pointer.dy);
    _endDrag();
    final sameColumn = columnOf(card, widget.columns) == column.id;
    // Within its column a card only moves for whoever may reorder.
    if (sameColumn && !widget.writable) return;
    // Let go where it was — held to edit its title: nothing moves.
    if (sameColumn && index == cards.indexWhere((c) => c.id == card.id)) {
      return;
    }
    await ref
        .read(kanbanViewModelProvider(widget.list.id).notifier)
        .moveCard(
          card,
          column,
          columnCards: cards,
          index: index,
          reorder: widget.writable,
        );
  }

  /// A card its delete symbol took away — with a moment to take it back.
  void _delete(Todo card) {
    ref.read(kanbanViewModelProvider(widget.list.id).notifier).deleteItem(card);
    // The board may be gone when "Undo" comes: it goes through the container.
    final container = ProviderScope.containerOf(context, listen: false);
    final listId = widget.list.id;
    final newCard = _newCard;
    showTodoDeletedSnackBar(
      context,
      title: card.title,
      onUndo: () {
        newCard.expectBack([card.id]);
        container
            .read(kanbanViewModelProvider(listId).notifier)
            .undoDeleteItem(card.id);
      },
    );
  }

  void _startDrag(Todo card) => setState(() {
    _dragging = card;
    _slot = null;
  });

  void _endDrag() {
    _columnScroll.stop();
    _edgeTimer?.cancel();
    _edgeTimer = null;
    _edgeDirection = 0;
    if (mounted) {
      setState(() {
        _dragging = null;
        _slot = null;
      });
    }
  }

  /// A card held at the left or right edge moves the board: the wide one scrolls, the
  /// phone turns the page.
  void _dragUpdate(DragUpdateDetails details) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final x = box.globalToLocal(details.globalPosition).dx;
    const edge = HiwiskiMetrics.kanbanEdgeZone;
    final direction = switch (x) {
      < edge => -1,
      _ when x > box.size.width - edge => 1,
      _ => 0,
    };
    if (direction == _edgeDirection) return;
    _edgeDirection = direction;
    _edgeTimer?.cancel();
    _edgeTimer = null;
    if (direction == 0) return;

    final pages = _pages;
    if (pages != null && pages.hasClients) {
      // Held for a moment, then the next page — and again if still held.
      _edgeTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
        final next = (_page + direction).clamp(0, widget.columns.length - 1);
        if (next != _page) {
          pages.animateToPage(
            next,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    } else if (_horizontal.hasClients) {
      _edgeTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        final position = _horizontal.position;
        _horizontal.jumpTo(
          (position.pixels + direction * HiwiskiMetrics.kanbanEdgeScrollStep)
              .clamp(position.minScrollExtent, position.maxScrollExtent),
        );
      });
    }
  }

  /// Claims a sideways scroll the board cannot follow any more — at its left or right
  /// end.
  ///
  /// A scrollable only claims what moves it; what nobody claims, the web engine hands
  /// back to the browser, and Safari reads a sideways swipe at the edge as "back".
  /// Claimed here, the engine keeps it. Only over the board: elsewhere the swipe still
  /// goes back. Registered last, so a column or the board that can still scroll comes
  /// first.
  void _keepSidewaysScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta;
    if (delta.dx.abs() <= delta.dy.abs()) return;
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (event) => event.respond(allowPlatformDefault: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final arranged = arrangeCards(widget.cards, widget.columns);
    return Listener(
      onPointerSignal: _keepSidewaysScroll,
      child: LayoutBuilder(
        key: _boardKey,
        builder: (context, constraints) {
          final wide =
              constraints.maxWidth >=
              2 * HiwiskiMetrics.kanbanColumnWidth +
                  _columnGap +
                  widget.padding.horizontal;
          return wide
              ? _WideBoard(
                  board: this,
                  arranged: arranged,
                  constraints: constraints,
                )
              : _PagedBoard(
                  board: this,
                  arranged: arranged,
                  constraints: constraints,
                );
        },
      ),
    );
  }

  /// Where the dragged card would land in [column], if it is over it.
  int? _slotIn(KanbanColumn column) => switch (_slot) {
    final slot? when slot.columnId == column.id => slot.index,
    _ => null,
  };

  void _showPage(int index) => setState(() => _page = index);
}

/// All columns side by side, scrolling sideways when they do not fit.
class _WideBoard extends StatelessWidget {
  const _WideBoard({
    required this.board,
    required this.arranged,
    required this.constraints,
  });

  final _KanbanBoardState board;
  final Map<String, List<Todo>> arranged;
  final BoxConstraints constraints;

  @override
  Widget build(BuildContext context) {
    final height = constraints.maxHeight - board.widget.padding.vertical;
    return Scrollbar(
      controller: board._horizontal,
      child: SingleChildScrollView(
        controller: board._horizontal,
        scrollDirection: .horizontal,
        padding: board.widget.padding,
        child: Row(
          crossAxisAlignment: .start,
          children: [
            for (final (index, column) in board.widget.columns.indexed) ...[
              if (index > 0) const SizedBox(width: _columnGap),
              SizedBox(
                width: HiwiskiMetrics.kanbanColumnWidth,
                child: _ColumnView(
                  column: column,
                  cards: arranged[column.id]!,
                  height: height,
                  board: board,
                  slot: board._slotIn(column),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One column at a time, with tabs above — the phone.
class _PagedBoard extends StatelessWidget {
  const _PagedBoard({
    required this.board,
    required this.arranged,
    required this.constraints,
  });

  final _KanbanBoardState board;
  final Map<String, List<Todo>> arranged;
  final BoxConstraints constraints;

  @override
  Widget build(BuildContext context) {
    final pages = board._pages ??= PageController(
      viewportFraction: _pageFraction,
    );
    if (board._page >= board.widget.columns.length) {
      board._page = board.widget.columns.length - 1;
    }
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        _ColumnTabs(
          columns: board.widget.columns,
          counts: {
            for (final column in board.widget.columns)
              column.id: arranged[column.id]!.length,
          },
          current: board._page,
          padding: .fromLTRB(
            board.widget.padding.left,
            board.widget.padding.top,
            board.widget.padding.right,
            HiwiskiMetrics.space8,
          ),
          onTap: (index) => pages.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, inner) => PageView.builder(
              key: TodoKeys.kanbanPages,
              controller: pages,
              itemCount: board.widget.columns.length,
              onPageChanged: board._showPage,
              itemBuilder: (context, index) {
                final column = board.widget.columns[index];
                return _KeepWhileDragging(
                  keep: board._dragging != null,
                  child: Padding(
                    padding: .only(
                      left: HiwiskiMetrics.space6,
                      right: HiwiskiMetrics.space6,
                      bottom: board.widget.padding.bottom,
                    ),
                    child: _ColumnView(
                      column: column,
                      cards: arranged[column.id]!,
                      height: inner.maxHeight - board.widget.padding.bottom,
                      board: board,
                      slot: board._slotIn(column),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Keeps a page alive while a card is dragged — the page it came from may scroll out
/// of sight, and its card has to stay to finish the drag.
class _KeepWhileDragging extends StatefulWidget {
  const _KeepWhileDragging({required this.keep, required this.child});

  final bool keep;
  final Widget child;

  @override
  State<_KeepWhileDragging> createState() => _KeepWhileDraggingState();
}

class _KeepWhileDraggingState extends State<_KeepWhileDragging>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keep;

  @override
  void didUpdateWidget(_KeepWhileDragging old) {
    super.didUpdateWidget(old);
    if (old.keep != widget.keep) updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// The row of column names above the phone's pages: where one is, and a tap jumps.
class _ColumnTabs extends StatelessWidget {
  const _ColumnTabs({
    required this.columns,
    required this.counts,
    required this.current,
    required this.padding,
    required this.onTap,
  });

  final List<KanbanColumn> columns;
  final Map<String, int> counts;
  final int current;
  final EdgeInsets padding;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return SingleChildScrollView(
      scrollDirection: .horizontal,
      padding: padding,
      child: Row(
        children: [
          for (final (index, column) in columns.indexed)
            Padding(
              padding: const .only(right: HiwiskiMetrics.space6),
              child: InkWell(
                key: TodoKeys.kanbanTab(column.id),
                borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
                onTap: () => onTap(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const .symmetric(
                    horizontal: HiwiskiMetrics.space10,
                    vertical: HiwiskiMetrics.space6,
                  ),
                  decoration: BoxDecoration(
                    color: index == current
                        ? scheme.secondaryContainer
                        : scheme.surfaceContainerLow,
                    borderRadius: const .all(
                      .circular(HiwiskiMetrics.radiusChip),
                    ),
                    border: .fromBorderSide(
                      BorderSide(
                        color: index == current
                            ? scheme.secondaryContainer
                            : scheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: .min,
                    spacing: HiwiskiMetrics.space6,
                    children: [
                      Container(
                        width: HiwiskiMetrics.dotSmall,
                        height: HiwiskiMetrics.dotSmall,
                        decoration: BoxDecoration(
                          color: context.tokens.accent(
                            accentOf(column.colorToken),
                          ),
                          shape: .circle,
                        ),
                      ),
                      Text(
                        column.name,
                        style: context.texts.labelLarge?.copyWith(
                          color: index == current
                              ? scheme.onSecondaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '${counts[column.id] ?? 0}',
                        style: context.tokens.text.entityKey,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One column: a color bar, name and count, the cards, and "+ Add card".
class _ColumnView extends StatelessWidget {
  const _ColumnView({
    required this.column,
    required this.cards,
    required this.height,
    required this.board,
    required this.slot,
  });

  final KanbanColumn column;
  final List<Todo> cards;
  final double height;
  final _KanbanBoardState board;

  /// Where the gap for a dragged card opens, if it hovers here.
  final int? slot;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = context.scheme;
    final accent = context.tokens.accent(accentOf(column.colorToken));
    final dragging = board._dragging;
    board._newCard.reveal(
      [for (final card in cards) card.id],
      position: () => switch (cards
          .map((card) => board._cardKeys[card.id]?.currentContext)
          .nonNulls
          .firstOrNull) {
        final inside? => Scrollable.maybeOf(inside)?.position,
        null => null,
      },
    );

    // The dragged card stays where it was, faded: removing its widget would end the
    // drag's callbacks with it.
    final items = <Widget>[];
    int position = 0;
    for (final card in cards) {
      final isDragged = card.id == dragging?.id;
      if (slot == position && !isDragged) items.add(const _Gap());
      final cardItem = Padding(
        key: board._newCard.keyOf(card.id),
        padding: const .only(bottom: HiwiskiMetrics.space8),
        child: _DraggableCard(
          key: board._keyOf(card),
          card: card,
          column: column,
          board: board,
        ),
      );
      items.add(
        board.widget.writable && !board.widget.preview
            ? RemovableRow(
                key: ValueKey(card.id),
                onRemoved: () => board._delete(card),
                child: cardItem,
              )
            : cardItem,
      );
      if (!isDragged) position++;
    }
    if (slot case final slot? when slot >= position) items.add(const _Gap());

    return DragTarget<Todo>(
      onWillAcceptWithDetails: (details) =>
          board.widget.mayMove(details.data) &&
          (board.widget.writable ||
              columnOf(details.data, board.widget.columns) != column.id),
      onMove: (details) => board._hover(column, cards, details.offset),
      onLeave: (_) => board._leave(column),
      onAcceptWithDetails: (details) =>
          board._drop(column, cards, details.data, details.offset),
      builder: (context, candidates, rejected) => AnimatedContainer(
        key: TodoKeys.kanbanColumn(column.id),
        duration: const Duration(milliseconds: 150),
        height: height,
        decoration: BoxDecoration(
          color: candidates.isNotEmpty
              ? scheme.surfaceContainer
              : scheme.surfaceContainerLow,
          borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
          border: .fromBorderSide(
            BorderSide(
              color: candidates.isNotEmpty ? accent : scheme.outlineVariant,
            ),
          ),
        ),
        clipBehavior: .antiAlias,
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Container(height: HiwiskiMetrics.barHeight, color: accent),
            Padding(
              padding: const .fromLTRB(
                HiwiskiMetrics.space12,
                HiwiskiMetrics.space10,
                HiwiskiMetrics.space12,
                HiwiskiMetrics.space8,
              ),
              child: Row(
                children: [
                  if (column.done) ...[
                    Icon(
                      HiwiskiSymbols.checkCircle,
                      size: HiwiskiMetrics.icon18,
                      color: accent,
                    ),
                    const SizedBox(width: HiwiskiMetrics.space6),
                  ],
                  Expanded(
                    child: Text(
                      column.name,
                      overflow: .ellipsis,
                      style: context.texts.titleSmall,
                    ),
                  ),
                  Text('${cards.length}', style: context.tokens.text.entityKey),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        l.kanbanEmptyColumn,
                        style: context.texts.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const .symmetric(
                        horizontal: HiwiskiMetrics.space8,
                      ),
                      children: items,
                    ),
            ),
            // Nothing is added straight into the done column: a new card is work to do.
            if (board.widget.writable && !board.widget.preview && !column.done)
              _AddCard(
                list: board.widget.list,
                column: column,
                onAdding: () => board._newCard.expect([
                  for (final card in board.widget.cards) card.id,
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

/// The gap that opens where a dragged card would land.
class _Gap extends StatelessWidget {
  const _Gap();

  @override
  Widget build(BuildContext context) => Container(
    height: HiwiskiMetrics.kanbanDropHeight,
    margin: const .only(bottom: HiwiskiMetrics.space8),
    decoration: BoxDecoration(
      color: context.scheme.primary.withValues(alpha: 0.08),
      borderRadius: const .all(.circular(HiwiskiMetrics.radiusMenu)),
      border: .fromBorderSide(
        BorderSide(color: context.scheme.primary.withValues(alpha: 0.4)),
      ),
    ),
  );
}

class _DraggableCard extends StatelessWidget {
  const _DraggableCard({
    super.key,
    required this.card,
    required this.column,
    required this.board,
  });

  final Todo card;
  final KanbanColumn column;
  final _KanbanBoardState board;

  @override
  Widget build(BuildContext context) {
    final editable = board.widget.writable && !board.widget.preview;
    final body = _CardView(
      card: card,
      done: column.done,
      preview: board.widget.preview,
      members: board.widget.members,
      deletable: editable,
    );
    // Held, the title is edited on the card — around the drag, which hands a hold
    // that does not move on to it.
    final onRenamed = editable
        ? (String title) => board.ref
              .read(kanbanViewModelProvider(board.widget.list.id).notifier)
              .renameItem(card, title)
        : null;
    if (!board.widget.mayMove(card)) {
      return RenamableRow(onRenamed: onRenamed, child: body);
    }

    // The pointer holds the card a little inside its top left corner, and the board
    // reads the pointer — not the card's edge — to find the gap.
    final feedback = Transform.translate(
      offset: HiwiskiMetrics.kanbanDragOffset,
      child: SizedBox(
        width: HiwiskiMetrics.kanbanColumnWidth - 2 * HiwiskiMetrics.space8,
        child: Material(
          elevation: HiwiskiMetrics.elevationDrag,
          borderRadius: const .all(.circular(HiwiskiMetrics.radiusMenu)),
          child: _CardView(
            card: card,
            done: column.done,
            preview: board.widget.preview,
            members: board.widget.members,
          ),
        ),
      ),
    );
    final placeholder = Opacity(opacity: 0.35, child: body);

    return RenamableRow(
      onRenamed: onRenamed,
      child: ItemDraggable<Todo>(
        data: card,
        feedback: feedback,
        childWhenDragging: placeholder,
        onDragStarted: () => board._startDrag(card),
        onDragUpdate: board._dragUpdate,
        onDragDone: board._endDrag,
        child: body,
      ),
    );
  }
}

/// A card: the box, title with the mono number, the meta line, tags. A tap opens the
/// task.
class _CardView extends ConsumerWidget {
  const _CardView({
    this.deletable = false,
    required this.card,
    required this.done,
    required this.preview,
    required this.members,
  });

  final Todo card;
  final bool done;
  final bool preview;
  final Map<String, Member> members;

  /// Whether the card shows the delete symbol — held, it deletes the task.
  final bool deletable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final meta = todoMeta(context, card, members);
    final editing = RenamableRow.editing(context);
    final shape = RoundedRectangleBorder(
      side: BorderSide(color: scheme.outlineVariant),
      borderRadius: const .all(.circular(HiwiskiMetrics.radiusMenu)),
    );
    // No clip: the content keeps its padding, and the ripple follows the shape.
    return Material(
      color: scheme.surface,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        key: TodoKeys.kanbanCard(card.id),
        // While the title is a field, a tap beside it does not open the card.
        onTap: editing
            ? null
            : () => preview
                  ? openPreviewOf(
                      context,
                      ref,
                      itemType: EntityTypes.todo,
                      itemId: card.id,
                    )
                  : TodoDetailRoute(
                      listId: card.listId,
                      todoId: card.id,
                    ).go(context),
        onLongPress: ItemDraggable.takesLongPress(context)
            ? null
            : RenamableRow.maybeOf(context)?.edit,
        child: Padding(
          padding: const .symmetric(
            horizontal: HiwiskiMetrics.space12,
            vertical: HiwiskiMetrics.space10,
          ),
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Row(
                crossAxisAlignment: .start,
                children: [
                  Expanded(
                    child: _CardTitle(card: card, done: done),
                  ),
                  if (deletable)
                    Transform.translate(
                      // Into the card's padding: the symbol needs its tap target, the
                      // card no extra height.
                      offset: const Offset(
                        HiwiskiMetrics.space8,
                        -HiwiskiMetrics.space8,
                      ),
                      child: DeleteHoldButton(
                        holdKey: TodoKeys.deleteTodo(card.id),
                      ),
                    ),
                ],
              ),
              if (meta.isNotEmpty)
                Padding(
                  padding: const .only(top: HiwiskiMetrics.space4),
                  child: Text(
                    meta,
                    style: context.texts.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (card.tags.isNotEmpty)
                Padding(
                  padding: const .only(top: HiwiskiMetrics.space6),
                  child: TagChips(raw: card.tags),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A card's title with its mono number; struck through in the done column.
class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.card, required this.done});

  final Todo card;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final style = context.texts.bodyLarge?.copyWith(
      fontWeight: .w500,
      decoration: done ? TextDecoration.lineThrough : null,
      color: done ? context.scheme.onSurfaceVariant : null,
    );
    return RenamableTitle(
      fieldKey: TodoKeys.titleField(card.id),
      text: card.title,
      style: style,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: card.title, style: style),
            if (card.entityKey != null)
              TextSpan(
                text: '  ${card.entityKey}',
                style: context.tokens.text.entityKey,
              ),
          ],
        ),
      ),
    );
  }
}

/// "+ Add card" at the bottom of a column — turns into a field in place, and stays
/// open for the next one.
class _AddCard extends ConsumerStatefulWidget {
  const _AddCard({
    required this.list,
    required this.column,
    required this.onAdding,
  });

  final TodoList list;
  final KanbanColumn column;

  /// Just before a card is added — the board follows it.
  final VoidCallback onAdding;

  @override
  ConsumerState<_AddCard> createState() => _AddCardState();
}

class _AddCardState extends ConsumerState<_AddCard> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!_focus.hasFocus && _controller.text.trim().isEmpty && mounted) {
      setState(() => _open = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus
      ..removeListener(_focusChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    _controller.clear();
    _focus.requestFocus();
    widget.onAdding();
    await ref
        .read(kanbanViewModelProvider(widget.list.id).notifier)
        .add(
          widget.list,
          title: title,
          // A new card starts with the list's tags (they can be removed on it).
          tags: tagIdsOf(widget.list.tags),
          columnId: widget.column.id,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    if (!_open) {
      return Padding(
        padding: const .only(
          left: HiwiskiMetrics.space4,
          right: HiwiskiMetrics.space4,
          bottom: HiwiskiMetrics.space4,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: TodoKeys.kanbanAdd(widget.column.id),
            onPressed: () {
              setState(() => _open = true);
              _focus.requestFocus();
            },
            icon: const Icon(HiwiskiSymbols.add),
            label: Text(l.kanbanAddCard),
          ),
        ),
      );
    }
    return Padding(
      padding: const .all(HiwiskiMetrics.space8),
      child: TextField(
        key: TodoKeys.kanbanNew(widget.column.id),
        controller: _controller,
        focusNode: _focus,
        textInputAction: .send,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          isDense: true,
          hintText: l.kanbanNewCardHint,
          suffixIcon: IconButton(
            icon: const Icon(HiwiskiSymbols.arrowUpward),
            tooltip: l.actionAdd,
            onPressed: _submit,
          ),
        ),
      ),
    );
  }
}

/// The slot a pointer at [y] points before, given the vertical middles of a column's
/// cards in order — `null` for a card the lazy list has not built.
///
/// An unbuilt card before the first built one lies above the viewport and counts as
/// passed. Skipped, as it used to be, a drop after the 20th card of a long scrolled
/// column landed around the 10th.
@visibleForTesting
int slotIndex(List<double?> middles, double y) {
  int index = 0;
  bool seenBuilt = false;
  for (final middle in middles) {
    if (middle == null) {
      if (!seenBuilt) index++;
      continue;
    }
    seenBuilt = true;
    if (y > middle) index++;
  }
  return index;
}
