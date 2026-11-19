import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../app/stores.dart';
import '../../../core/common/command.dart';
import '../../../core/common/wire.dart';
import '../../../domain/board/board_items.dart';
import '../../../domain/board/widget_kinds.dart';

part 'dashboard_view_model.g.dart';

/// `moveWidget`, run by a view: it shows the command running and reacts to how it ended.
final moveWidgetMutation = Mutation<bool>(
  label: 'dashboardViewModel.moveWidget',
);

/// `swapWidgets`, run by a view: it shows the command running and reacts to how it ended.
final swapWidgetsMutation = Mutation<bool>(
  label: 'dashboardViewModel.swapWidgets',
);

/// The dashboard: set up **in the app**, shown **in the browser** of a wall tablet.
@immutable
class const DashboardState({
  required final Board board,
  required final List<BoardWidget> widgets,

  /// Where the tablet opens it.
  required final String serverAddress,
});

@riverpod
Stream<List<Board>> _boards(Ref ref) =>
    ref.watch(boardRepositoryProvider).watchBoards();

@riverpod
Stream<List<BoardWidget>> _widgets(Ref ref, String boardId) =>
    ref.watch(boardRepositoryProvider).watchWidgets(boardId);

@riverpod
class DashboardViewModel extends _$DashboardViewModel {
  @override
  Future<DashboardState> build() async {
    final serverAddress = ref.watch(
      sessionProvider.select((s) => s.serverAddress ?? ''),
    );
    final answered = ref.watch(syncStatusProvider.select((s) => s.answered));
    final repository = ref.watch(boardRepositoryProvider);
    final board = await repository.boardOf(
      BoardKinds.dashboard,
      await ref.watch(_boardsProvider.future),
      answered: answered,
    );
    // Too early to tell: rebuilt as soon as the sync answers or the board arrives.
    if (board == null) return Completer<DashboardState>().future;
    return DashboardState(
      board: board,
      widgets: await ref.watch(_widgetsProvider(board.id).future),
      serverAddress: serverAddress,
    );
  }

  /// A new tile of [kind], placed in the first free cell.
  Future<void> addWidget(WidgetKind kind) async {
    final current = state.value;
    if (current == null) return;
    await ref
        .read(boardRepositoryProvider)
        .addWidget(
          board: current.board,
          kind: kind.id,
          existing: current.widgets,
        );
  }

  Future<void> deleteWidget(BoardWidget widget) =>
      ref.read(boardRepositoryProvider).deleteWidget(widget);

  @command
  Future<bool> swapWidgets(
    BoardWidget dragged,
    BoardWidget target,
    List<BoardWidget> all, {
    required int columns,
  }) => ref
      .read(boardRepositoryProvider)
      .swapWidgets(dragged, target, all, columns: columns);

  @command
  Future<bool> moveWidget(
    BoardWidget widget,
    List<BoardWidget> others,
    int x,
    int y, {
    int? width,
    int? height,
    required int columns,
  }) => ref
      .read(boardRepositoryProvider)
      .moveWidget(
        widget,
        others,
        x,
        y,
        width: width,
        height: height,
        columns: columns,
      );

  Future<void> updateBoard(Board board, {int? columns}) =>
      ref.read(boardRepositoryProvider).updateBoard(board, columns: columns);

  /// A new address: the old one stops working at once.
  Future<void> regenerateToken(Board board) =>
      ref.read(boardRepositoryProvider).regenerateToken(board);
}
