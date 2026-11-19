import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/notice_bar.dart';
import '../page_view_model.dart';
import 'page_body.dart';

/// A page in a link's preview, looked up by its id.
class PagePreview extends ConsumerWidget {
  const PagePreview({super.key, required this.pageId});

  final String pageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(pageViewModelProvider(pageId))
        .when(
          skipLoadingOnReload: true,
          loading: () => const SizedBox.shrink(),
          error: (error, _) => NoticeBar.failure(context, error: error),
          data: (state) => state == null
              ? const SizedBox.shrink()
              : PageBody(page: state.page, preview: true),
        );
  }
}
