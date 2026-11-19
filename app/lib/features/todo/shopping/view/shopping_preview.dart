import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../view/list_intro.dart';
import '../shopping_view_model.dart';
import 'shopping_intro.dart';
import 'shopping_rows.dart';

/// A shopping list as a link's preview shows it.
class ShoppingPreview extends ConsumerWidget {
  const ShoppingPreview({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(shoppingViewModelProvider(listId))
        .when(
          skipLoadingOnReload: true,
          loading: () => const SizedBox.shrink(),
          error: (error, _) => NoticeBar.failure(context, error: error),
          data: (state) => state == null
              ? const SizedBox.shrink()
              : _ShoppingPreviewBody(listId: listId, state: state),
        );
  }
}

class _ShoppingPreviewBody extends StatelessWidget {
  const _ShoppingPreviewBody({required this.listId, required this.state});

  final String listId;
  final ShoppingState state;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        if (ListIntro.shows(state.list))
          ShoppingIntro(listId: listId, state: state),
        if (state.items.isEmpty)
          Text(
            l.todoListEmpty,
            style: context.texts.bodyMedium?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          )
        else
          ShoppingRows(listId: listId, state: state, preview: true),
      ],
    );
  }
}
