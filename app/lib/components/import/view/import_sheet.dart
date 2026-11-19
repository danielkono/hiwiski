import 'package:flutter/material.dart';
import 'package:flutter_riverpod/experimental/mutation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/hiwiski_sheet.dart';
import '../../../core/ui/list_kind_tile.dart';
import '../../../core/ui/loading_strip.dart';
import '../../../core/ui/notice_bar.dart';
import '../../../domain/transfer/transfer_models.dart';
import '../import_view_model.dart';
import 'import_keys.dart';

/// "Import": what the picked files hold — lists, pages, images, and what could not
/// be read — before any of it is created. "Insert" creates it.
Future<void> showImportSheet(
  BuildContext context, {
  required ImportSource source,
}) => showHiwiskiSheet<void>(
  context: context,
  title: L.of(context).importTitle,
  builder: (context) => _ImportBody(source: source),
);

class _ImportBody extends ConsumerWidget {
  const _ImportBody({required this.source});

  final ImportSource source;

  Future<void> _take(BuildContext context, WidgetRef ref) async {
    // A second tap while it ran created everything twice.
    if (ref.read(takeImportMutation).isPending) return;
    final l = L.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ImportResult result;
    try {
      result = await takeImportMutation.run(
        ref,
        (tsx) => tsx.get(importViewModelProvider(source).notifier).take(),
      );
    } on Object {
      // Shown by the sheet, from the mutation.
      return;
    }
    final done = [
      if (result.lists > 0) l.importDoneLists(result.lists),
      if (result.pages > 0) l.importDonePages(result.pages),
    ].join(' ');
    messenger.showSnackBar(SnackBar(content: Text(done)));
    navigator.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final plan = ref.watch(importViewModelProvider(source));
    final taking = ref.watch(takeImportMutation);
    final tags = plan.tagNames;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        LoadingStrip(loading: taking.isPending),
        if (taking case MutationError(:final error))
          Padding(
            padding: const .only(bottom: HiwiskiMetrics.space12),
            child: NoticeBar.failure(context, error: error),
          ),
        Text(
          plan.isEmpty ? l.importEmpty : l.importIntro,
          style: context.texts.bodyMedium?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
        if (plan.lists.isNotEmpty) ...[
          _Heading(l.archiveGroupLists),
          for (final list in plan.lists)
            _Row(
              icon: listKindIcon(list.kind),
              title: list.name,
              detail: l.importListLine(list.tasks.length, list.doneCount),
            ),
        ],
        if (plan.pages.isNotEmpty) ...[
          _Heading(l.archiveGroupPages),
          ..._pageRows(context, plan),
        ],
        if (plan.images.isNotEmpty || tags.isNotEmpty)
          Padding(
            padding: const .only(top: HiwiskiMetrics.space16),
            child: Text(
              [
                if (plan.images.isNotEmpty)
                  l.importImageCount(plan.images.length),
                if (tags.isNotEmpty) l.importTags(tags.join(', ')),
              ].join(' · '),
              style: context.texts.bodySmall?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
          ),
        if (plan.skipped.isNotEmpty) ...[
          _Heading(l.importSkippedTitle, key: ImportKeys.skipped),
          for (final file in plan.skipped)
            _Row(
              icon: HiwiskiSymbols.errorOutline,
              title: file.path,
              detail: switch (file.reason) {
                .unsupported => l.importSkipUnsupported,
                .brokenArchive => l.importSkipBrokenArchive,
                .notText => l.importSkipNotText,
                .noTasks => l.importSkipNoTasks,
                .tooLong => l.importSkipTooLong,
              },
            ),
        ],
        SheetActions(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.actionCancel),
            ),
            FilledButton(
              key: ImportKeys.take,
              onPressed: plan.isEmpty || taking.isPending
                  ? null
                  : () => _take(context, ref),
              child: Text(l.importTake),
            ),
          ],
        ),
      ],
    );
  }

  /// The pages as their tree, each below its parent — up to [_shownPages]: a wiki of
  /// hundreds of pages is named by its first ones and a count.
  List<Widget> _pageRows(BuildContext context, ImportPlan plan) {
    final rows = <Widget>[];
    void add(TransferPage page, int depth) {
      if (rows.length < _shownPages) {
        rows.add(
          _Row(
            icon: page.children.isEmpty
                ? HiwiskiSymbols.description
                : HiwiskiSymbols.folder,
            title: page.title,
            depth: depth,
          ),
        );
      }
      for (final child in page.children) {
        add(child, depth + 1);
      }
    }

    for (final page in plan.pages) {
      add(page, 0);
    }
    final more = plan.pageCount - rows.length;
    return [
      ...rows,
      if (more > 0)
        Padding(
          padding: const .only(top: HiwiskiMetrics.space4),
          child: Text(
            L.of(context).importMore(more),
            style: context.texts.bodySmall?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
        ),
    ];
  }
}

const _shownPages = 40;

class _Heading extends StatelessWidget {
  const _Heading(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .only(
      top: HiwiskiMetrics.space16,
      bottom: HiwiskiMetrics.space6,
    ),
    child: Text(label, style: context.tokens.text.sectionLabel),
  );
}

/// One thing the import holds: a symbol, its name, and what there is to say about it.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.detail,
    this.depth = 0,
  });

  final IconData icon;
  final String title;
  final String? detail;

  /// How far below the root a page lies — its indent.
  final int depth;

  @override
  Widget build(BuildContext context) => Padding(
    padding: .only(
      left: depth * HiwiskiMetrics.space16,
      top: HiwiskiMetrics.space4,
      bottom: HiwiskiMetrics.space4,
    ),
    child: Row(
      crossAxisAlignment: .start,
      spacing: HiwiskiMetrics.space8,
      children: [
        Icon(
          icon,
          size: HiwiskiMetrics.icon18,
          color: context.scheme.onSurfaceVariant,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Text(title, style: context.texts.bodyMedium),
              if (detail case final detail?)
                Text(
                  detail,
                  style: context.texts.bodySmall?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
