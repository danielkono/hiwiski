import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/ui/hiwiski_sheet.dart';
import '../../../../domain/wiki/wiki_models.dart';
import '../../../../domain/wiki/wiki_page.dart';
import '../page_view_model.dart';

/// "Move" — attach the branch somewhere else.
///
/// **The shares are right afterwards:** an own share
/// survives the move, an inherited one comes from the new place. The server computes
/// that; here only the target is chosen.
Future<void> showMoveSheet(BuildContext context, {required WikiPage page}) {
  return showHiwiskiSheet<void>(
    context: context,
    title: L.of(context).wikiMove,
    builder: (context) => _MoveBody(page: page),
  );
}

class _MoveBody extends ConsumerWidget {
  const _MoveBody({required this.page});

  final WikiPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final targets =
        ref.watch(pageViewModelProvider(page.id)).value?.moveTargets ??
        const [];

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Text(l.wikiMoveTo),
        const SizedBox(height: HiwiskiMetrics.space12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(HiwiskiSymbols.folder),
          title: Text(l.wikiMoveRoot),
          selected: page.parentId == null,
          onTap: () => _move(context, ref, null),
        ),
        for (final node in targets) ..._options(context, ref, node, 0),
      ],
    );
  }

  List<Widget> _options(
    BuildContext context,
    WidgetRef ref,
    WikiNode node,
    int depth,
  ) {
    return [
      ListTile(
        contentPadding: .only(left: depth * 16.0),
        leading: Icon(
          node.isRecipe
              ? HiwiskiSymbols.restaurant
              : HiwiskiSymbols.description,
          size: HiwiskiMetrics.icon18,
        ),
        title: Text(node.page.title),
        selected: page.parentId == node.page.id,
        onTap: () => _move(context, ref, node.page.id),
      ),
      for (final child in node.children)
        ..._options(context, ref, child, depth + 1),
    ];
  }

  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    String? parentId,
  ) async {
    await ref
        .read(pageViewModelProvider(page.id).notifier)
        .move(page, parentId);
    if (context.mounted) Navigator.of(context).pop();
  }
}
