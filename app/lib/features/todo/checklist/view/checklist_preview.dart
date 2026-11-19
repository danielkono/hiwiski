import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../view/list_intro.dart';
import '../checklist_view_model.dart';
import 'checklist_intro.dart';
import 'checklist_row.dart';

/// A task list as a link's preview shows it: its description and rows, boxes can be
/// ticked, a row opens its own preview.
class ChecklistPreview extends ConsumerWidget {
  const ChecklistPreview({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(checklistViewModelProvider(listId))
        .when(
          skipLoadingOnReload: true,
          loading: () => const SizedBox.shrink(),
          error: (error, _) => NoticeBar.failure(context, error: error),
          data: (state) => state == null
              ? const SizedBox.shrink()
              : _ChecklistPreviewBody(listId: listId, state: state),
        );
  }
}

class _ChecklistPreviewBody extends StatelessWidget {
  const _ChecklistPreviewBody({required this.listId, required this.state});

  final String listId;
  final ChecklistState state;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        if (ListIntro.shows(state.list))
          ChecklistIntro(listId: listId, state: state),
        if (state.items.isEmpty)
          Text(
            l.todoListEmpty,
            style: context.texts.bodyMedium?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          )
        else
          for (final todo in state.items)
            ChecklistRow(
              listId: listId,
              state: state,
              todo: todo,
              preview: true,
            ),
      ],
    );
  }
}
