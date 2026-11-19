import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/shell/breakpoints.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/page_header.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../../../core/ui/hiwiski_sheet.dart';
import '../../../../core/ui/states.dart';
import '../../../../domain/board/board_items.dart';
import '../../../../domain/board/widget_kinds.dart';
import '../../view/board_grid.dart';
import '../../widget_config/view/widget_config_sheet.dart';
import '../../widget_tile/view/widget_tile.dart';
import '../dashboard_view_model.dart';

/// Setting up the dashboard — **in the app**; it is shown in the browser.
///
/// "Grid with a selectable number of columns (1, 2, 3, 4, 6, 8). 'Edit' turns on
/// arrange mode […]. **Gaps are allowed, overlaps are rejected by the board** —
/// a tile underneath another would be invisible, and nobody would know where it
/// went."
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _arranging = false;

  /// "If the screen gets too narrow (cell width below 150), the tiles fall below each
  /// other in reading order. That way the same board that hangs on the wall can be
  /// set up on the phone."

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final header = PageHeader(
      title: l.boardDashboard,
      onBack: () => Navigator.of(context).pop(),
    );
    return ref
        .watch(dashboardViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(header: header, error: error),
          data: (state) {
            final l = L.of(context);
            final padding = Breakpoint.of(context).pagePadding;
            return HiwiskiPage(
              header: PageHeader(
                title: l.boardDashboard,
                onBack: () => Navigator.of(context).pop(),
                trailing: [
                  IconButton(
                    icon: Icon(
                      _arranging ? HiwiskiSymbols.check : HiwiskiSymbols.tune,
                    ),
                    tooltip: _arranging ? l.boardDone : l.boardArrange,
                    onPressed: () => setState(() => _arranging = !_arranging),
                  ),
                ],
              ),
              body: ListView(
                padding: padding.add(
                  const .only(bottom: HiwiskiMetrics.space32),
                ),
                children: [
                  _Address(
                    board: state.board,
                    serverAddress: state.serverAddress,
                  ),
                  const Divider(height: HiwiskiMetrics.space32),
                  _Columns(board: state.board),
                  const SizedBox(height: HiwiskiMetrics.space16),
                  _Grid(state: state, arranging: _arranging),
                ],
              ),
              floatingActionButton: const _AddMenu(),
            );
          },
        );
  }
}

/// "At the top of the screen is the **address** in mono with 'Copy', 'Show as
/// QR' and 'Regenerate'."
class _Address extends ConsumerWidget {
  const _Address({required this.board, required this.serverAddress});

  final Board board;
  final String serverAddress;

  String _url(WidgetRef ref) =>
      '$serverAddress${KioskRoute(token: board.token ?? '').location}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final address = _url(ref);

    return Column(
      crossAxisAlignment: .start,
      children: [
        Text(l.boardAddress, style: context.tokens.text.sectionLabel),
        const SizedBox(height: HiwiskiMetrics.space4),
        Text(
          l.boardDashboardHint,
          style: context.texts.bodySmall?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space8),
        SelectableText(address, style: context.tokens.text.monoSmall),
        const SizedBox(height: HiwiskiMetrics.space8),
        Wrap(
          spacing: HiwiskiMetrics.space8,
          children: [
            TextButton.icon(
              icon: const Icon(HiwiskiSymbols.contentCopy),
              label: Text(l.boardCopy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: address));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(l.boardCopied)));
                }
              },
            ),
            TextButton.icon(
              icon: const Icon(HiwiskiSymbols.qrCode),
              label: Text(l.boardShowQr),
              onPressed: () => showHiwiskiSheet<void>(
                context: context,
                title: l.boardShowQr,
                builder: (context) => Center(
                  child: QrImageView(
                    data: address,
                    size: HiwiskiMetrics.qrCodeLarge,
                    // Dark on light in both themes: many cameras do not read a QR code on a
                    // dark background.
                    backgroundColor: context.tokens.code.background,
                    eyeStyle: QrEyeStyle(
                      eyeShape: .square,
                      color: context.tokens.code.foreground,
                    ),
                    dataModuleStyle: QrDataModuleStyle(
                      dataModuleShape: .square,
                      color: context.tokens.code.foreground,
                    ),
                  ),
                ),
              ),
            ),
            TextButton.icon(
              icon: const Icon(HiwiskiSymbols.refresh),
              label: Text(l.boardRegenerate),
              style: TextButton.styleFrom(
                foregroundColor: context.scheme.error,
              ),
              onPressed: () => _confirmRegenerate(context, ref),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmRegenerate(BuildContext context, WidgetRef ref) async {
    final l = L.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.boardRegenerate),
        // With the note that the old address is dead immediately.
        content: Text(l.boardRegenerateBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.boardRegenerate),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref
          .read(dashboardViewModelProvider.notifier)
          .regenerateToken(board);
    }
  }
}

class _Columns extends ConsumerWidget {
  const _Columns({required this.board});

  final Board board;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    // Wraps: on the phone the label and six chips are wider than the screen.
    return Wrap(
      crossAxisAlignment: .center,
      runSpacing: HiwiskiMetrics.space6,
      children: [
        Padding(
          padding: const .only(right: HiwiskiMetrics.space12),
          child: Text(l.boardColumns, style: context.tokens.text.sectionLabel),
        ),
        for (final count in const [1, 2, 3, 4, 6, 8])
          Padding(
            padding: const .only(right: HiwiskiMetrics.space6),
            child: ChoiceChip(
              label: Text('$count'),
              selected: board.columns == count,
              onSelected: (_) => ref
                  .read(dashboardViewModelProvider.notifier)
                  .updateBoard(board, columns: count),
            ),
          ),
      ],
    );
  }
}

class _Grid extends ConsumerWidget {
  const _Grid({required this.state, required this.arranging});

  final DashboardState state;
  final bool arranging;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final widgets = state.widgets;
    final board = state.board;

    if (widgets.isEmpty) {
      return Padding(
        padding: const .symmetric(vertical: HiwiskiMetrics.space32),
        child: EmptyState(
          icon: HiwiskiSymbols.dashboard,
          message: l.boardDashboardEmpty,
        ),
      );
    }

    return BoardGrid<BoardWidget>(
      tiles: widgets,
      placeOf: (tile) =>
          (x: tile.gridX, y: tile.gridY, width: tile.gridW, height: tile.gridH),
      columns: board.columns,
      tilePadding: const .all(HiwiskiMetrics.space4),
      stackedGap: HiwiskiMetrics.space14,
      tileBuilder: (tile) => _Tile(
        widget: tile,
        arranging: arranging,
        others: widgets,
        columns: board.columns,
      ),
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({
    required this.widget,
    required this.arranging,
    required this.others,
    required this.columns,
  });

  final BoardWidget widget;
  final bool arranging;
  final List<BoardWidget> others;

  /// The board's columns — no tile goes past them.
  final int columns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final content = Card(
      shape: arranging
          ? RoundedRectangleBorder(
              side: BorderSide(
                color: context.scheme.primary,
                width: HiwiskiMetrics.strokeBold,
              ),
              borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
            )
          : null,
      child: Padding(
        padding: const .all(HiwiskiMetrics.space12),
        // In the grid a tile has its cells' height and scrolls inside it; on the
        // phone the tiles stand one below the other and are as high as they are.
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: .stretch,
            children: [
              if (arranging)
                Row(
                  mainAxisAlignment: .end,
                  children: [
                    IconButton(
                      iconSize: HiwiskiMetrics.icon18,
                      icon: const Icon(HiwiskiSymbols.aspectRatio),
                      tooltip: l.boardSize,
                      onPressed: () => _resize(context, ref),
                    ),
                    IconButton(
                      iconSize: HiwiskiMetrics.icon18,
                      icon: const Icon(HiwiskiSymbols.tune),
                      tooltip: l.boardConfigure,
                      onPressed: () =>
                          showWidgetConfigSheet(context, widget: widget),
                    ),
                    IconButton(
                      iconSize: HiwiskiMetrics.icon18,
                      icon: const Icon(HiwiskiSymbols.delete),
                      tooltip: l.boardRemove,
                      onPressed: () => ref
                          .read(dashboardViewModelProvider.notifier)
                          .deleteWidget(widget),
                    ),
                  ],
                ),
              if (constraints.hasBoundedHeight)
                Expanded(
                  child: SingleChildScrollView(
                    child: WidgetTile(widget: widget),
                  ),
                )
              else
                WidgetTile(widget: widget),
            ],
          ),
        ),
      ),
    );

    if (!arranging) return content;

    // Drag with a long press. The rejection on overlap says so — otherwise
    // the tile would seem to vanish.
    return LongPressDraggable<BoardWidget>(
      data: widget,
      feedback: Opacity(
        opacity: 0.8,
        child: SizedBox.fromSize(
          size: HiwiskiMetrics.dragFeedbackSize,
          child: content,
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: content),
      child: DragTarget<BoardWidget>(
        onAcceptWithDetails: (details) => _swap(context, ref, details.data),
        builder: (context, candidate, rejected) => content,
      ),
    );
  }

  Future<void> _swap(
    BuildContext context,
    WidgetRef ref,
    BoardWidget dragged,
  ) async {
    if (dragged.id == widget.id) return;
    final ok = await swapWidgetsMutation.run(
      ref,
      (tsx) => tsx
          .get(dashboardViewModelProvider.notifier)
          .swapWidgets(dragged, widget, others, columns: columns),
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(L.of(context).boardOccupied)));
    }
  }

  Future<void> _setSize(
    BuildContext context,
    WidgetRef ref,
    BoardWidget current,
    List<BoardWidget> siblings, {
    int? width,
    int? height,
  }) async {
    final ok = await moveWidgetMutation.run(
      ref,
      (tsx) => tsx
          .get(dashboardViewModelProvider.notifier)
          .moveWidget(
            current,
            siblings,
            current.gridX,
            current.gridY,
            width: width,
            height: height,
            columns: columns,
          ),
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(L.of(context).boardOccupied)));
    }
  }

  Future<void> _resize(BuildContext context, WidgetRef ref) async {
    final l = L.of(context);
    await showHiwiskiSheet<void>(
      context: context,
      title: l.boardSize,
      // **The tile as it is now, not as it was when opened.** The sheet used to read the row
      // it was opened with: the selection stayed at 2 × 2 although the tile grew, and
      // the second change sent the old width and the old
      // version along.
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final all =
              // A Consumer's builder is a build.
              // ignore: many_lints/avoid_ref_watch_outside_build
              ref.watch(dashboardViewModelProvider).value?.widgets ?? const [];
          final current =
              all.where((row) => row.id == widget.id).firstOrNull ?? widget;
          final others = [
            for (final row in all)
              if (row.id != widget.id) row,
          ];
          return Column(
            crossAxisAlignment: .stretch,
            children: [
              for (final entry in {
                l.boardWidth: true,
                l.boardHeight: false,
              }.entries)
                Padding(
                  padding: const .only(bottom: HiwiskiMetrics.space12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: HiwiskiMetrics.labelColumnWidth,
                        child: Text(entry.key),
                      ),
                      // Only widths that fit from where the tile stands.
                      for (final size in const [1, 2, 3, 4])
                        if (!entry.value || current.gridX + size <= columns)
                          Padding(
                            padding: const .only(right: HiwiskiMetrics.space6),
                            child: ChoiceChip(
                              label: Text('$size'),
                              selected: entry.value
                                  ? current.gridW == size
                                  : current.gridH == size,
                              onSelected: (_) => unawaited(
                                _setSize(
                                  context,
                                  ref,
                                  current,
                                  others,
                                  width: entry.value ? size : null,
                                  height: entry.value ? null : size,
                                ),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AddMenu extends ConsumerWidget {
  const _AddMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    return MenuAnchor(
      menuChildren: [
        // On the dashboard **all** kinds are available — the restriction to
        // calendar and tasks only applies to the start board.
        for (final kind in WidgetKind.all)
          MenuItemButton(
            onPressed: () async {
              await ref
                  .read(dashboardViewModelProvider.notifier)
                  .addWidget(kind);
            },
            child: Text(widgetKindLabel(l, kind)),
          ),
      ],
      builder: (context, anchor, _) => FloatingActionButton(
        tooltip: l.boardAddWidget,
        onPressed: () => anchor.isOpen ? anchor.close() : anchor.open(),
        child: const Icon(HiwiskiSymbols.add),
      ),
    );
  }
}
