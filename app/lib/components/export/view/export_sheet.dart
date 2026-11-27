import 'package:flutter/material.dart';
import 'package:flutter_riverpod/experimental/mutation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/archive_files.dart';
import '../../../core/ui/hiwiski_sheet.dart';
import '../../../core/ui/loading_strip.dart';
import '../../../core/ui/notice_bar.dart';
import '../../../domain/common/item_ref.dart';
import '../../../domain/transfer/transfer_bundle.dart';
import '../../../domain/wiki/mindmap.dart';
import '../export_view_model.dart';
import 'export_keys.dart';

/// "Export": what goes into the file, then the file — a download in the browser, the
/// system's save dialog everywhere else, which on a phone also leads to the Files app
/// or a cloud drive.
///
/// [drawMindmap] draws a mind map among the pages as a picture, to go along.
Future<void> showExportSheet(
  BuildContext context, {
  required ItemRef item,
  MindmapDrawing Function(BuildContext context)? drawMindmap,
}) => showHiwiskiSheet<void>(
  context: context,
  title: L.of(context).exportTitle,
  builder: (context) => _ExportBody(item: item, drawMindmap: drawMindmap),
);

class _ExportBody extends ConsumerStatefulWidget {
  const _ExportBody({required this.item, required this.drawMindmap});

  final ItemRef item;
  final MindmapDrawing Function(BuildContext context)? drawMindmap;

  @override
  ConsumerState<_ExportBody> createState() => _ExportBodyState();
}

class _ExportBodyState extends ConsumerState<_ExportBody> {
  bool _withDone = true;
  bool _withSubpages = true;
  bool _withImages = true;
  bool _withMindmaps = true;

  Future<void> _export() async {
    // A second tap while it ran built and offered the file twice.
    if (ref.read(exportMutation).isPending) return;
    final messenger = ScaffoldMessenger.of(context);
    final saved = L.of(context).exportSaved;
    // Taken now: the drawing goes on should the sheet close meanwhile.
    final draw = _withMindmaps ? widget.drawMindmap?.call(context) : null;
    final ExportedFile file;
    try {
      file = await exportMutation.run(
        ref,
        (tsx) => tsx
            .get(exportViewModelProvider(widget.item).notifier)
            .export(
              withDone: _withDone,
              withSubpages: _withSubpages,
              withImages: _withImages,
              drawMindmap: draw,
            ),
      );
    } on Object {
      // Shown by the sheet, from the mutation.
      return;
    }
    // Dismissing the save dialog is no error: the sheet stays, to try again.
    if (!await saveArchive(file.name, file.bytes)) return;
    messenger.showSnackBar(SnackBar(content: Text(saved)));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final running = ref.watch(exportMutation);
    return ref
        .watch(exportViewModelProvider(widget.item))
        .when(
          skipLoadingOnReload: true,
          loading: () => const LoadingStrip(loading: true),
          error: (error, _) => NoticeBar.failure(context, error: error),
          data: (state) {
            if (state == null) return const SizedBox.shrink();
            final images = _withSubpages
                ? state.imagesWithSubpages
                : state.images;
            final mindmaps = switch ((widget.drawMindmap, _withSubpages)) {
              (null, _) => 0,
              (_, true) => state.mindmapsWithSubpages,
              (_, false) => state.mindmaps,
            };
            return Column(
              crossAxisAlignment: .stretch,
              children: [
                LoadingStrip(loading: running.isPending),
                if (running case MutationError(:final error))
                  Padding(
                    padding: const .only(bottom: HiwiskiMetrics.space12),
                    child: NoticeBar.failure(context, error: error),
                  ),
                Text(state.name, style: context.texts.titleMedium),
                const SizedBox(height: HiwiskiMetrics.space4),
                Text(
                  state.isPage
                      ? l.exportPageHint
                      : l.exportListHint(state.tasks),
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: HiwiskiMetrics.space8),
                if (!state.isPage && state.doneTasks > 0)
                  SwitchListTile(
                    key: ExportKeys.withDone,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.exportWithDone),
                    subtitle: Text(l.exportDoneCount(state.doneTasks)),
                    value: _withDone,
                    onChanged: (value) => setState(() => _withDone = value),
                  ),
                if (state.subpages > 0)
                  SwitchListTile(
                    key: ExportKeys.withSubpages,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.exportWithSubpages),
                    subtitle: Text(l.exportSubpageCount(state.subpages)),
                    value: _withSubpages,
                    onChanged: (value) => setState(() => _withSubpages = value),
                  ),
                if (images > 0)
                  SwitchListTile(
                    key: ExportKeys.withImages,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.exportWithImages),
                    subtitle: Text(l.exportImageCount(images)),
                    value: _withImages,
                    onChanged: (value) => setState(() => _withImages = value),
                  ),
                if (mindmaps > 0)
                  SwitchListTile(
                    key: ExportKeys.withMindmaps,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.exportWithMindmaps),
                    subtitle: Text(l.exportMindmapCount(mindmaps)),
                    value: _withMindmaps,
                    onChanged: (value) => setState(() => _withMindmaps = value),
                  ),
                SheetActions(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l.actionCancel),
                    ),
                    FilledButton(
                      key: ExportKeys.run,
                      onPressed: running.isPending ? null : _export,
                      child: Text(l.exportAction),
                    ),
                  ],
                ),
              ],
            );
          },
        );
  }
}
