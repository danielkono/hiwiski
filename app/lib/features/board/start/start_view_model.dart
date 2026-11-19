import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../app/stores.dart';
import '../../../core/common/wire.dart';
import '../../../domain/board/board_items.dart';
import '../../../domain/board/widget_kinds.dart';

part 'start_view_model.g.dart';

/// The start board: the member's own tiles, greeted by name.
@immutable
class const StartState({
  required final Board board,
  required final List<BoardWidget> widgets,

  /// Whom to greet.
  required final String name,
});

@riverpod
Stream<List<Board>> _boards(Ref ref) =>
    ref.watch(boardRepositoryProvider).watchBoards();

@riverpod
Stream<List<BoardWidget>> _widgets(Ref ref, String boardId) =>
    ref.watch(boardRepositoryProvider).watchWidgets(boardId);

@riverpod
class StartViewModel extends _$StartViewModel {
  @override
  Future<StartState> build() async {
    final name = ref.watch(
      sessionProvider.select((s) => s.member?.displayName ?? ''),
    );
    final answered = ref.watch(syncStatusProvider.select((s) => s.answered));
    final repository = ref.watch(boardRepositoryProvider);
    final board = await repository.boardOf(
      BoardKinds.start,
      await ref.watch(_boardsProvider.future),
      answered: answered,
    );
    // Too early to tell: rebuilt as soon as the sync answers or the board arrives.
    if (board == null) return Completer<StartState>().future;
    return StartState(
      board: board,
      widgets: await ref.watch(_widgetsProvider(board.id).future),
      name: name,
    );
  }

  /// A new tile of [kind], placed after the others.
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
}
