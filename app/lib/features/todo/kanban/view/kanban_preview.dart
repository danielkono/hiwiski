import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/notice_bar.dart';
import '../../view/list_intro.dart';
import '../kanban_view_model.dart';
import 'kanban_intro.dart';
import 'kanban_state_board.dart';

/// A board as a link's preview shows it: on its page the board fills the screen; in a
/// preview it gets most of one. Cards move, none is added.
class KanbanPreview extends ConsumerWidget {
  const KanbanPreview({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(kanbanViewModelProvider(listId))
        .when(
          skipLoadingOnReload: true,
          loading: () => const SizedBox.shrink(),
          error: (error, _) => NoticeBar.failure(context, error: error),
          data: (state) => state == null || state.columns.isEmpty
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    if (ListIntro.shows(state.list))
                      KanbanIntro(listId: listId, state: state),
                    SizedBox(
                      height:
                          MediaQuery.sizeOf(context).height *
                          _previewBoardShare,
                      child: KanbanStateBoard(
                        state: state,
                        padding: .zero,
                        preview: true,
                      ),
                    ),
                  ],
                ),
        );
  }
}

/// How much of the screen's height a board gets in a preview.
const _previewBoardShare = 0.6;
