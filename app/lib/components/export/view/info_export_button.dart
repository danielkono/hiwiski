import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../domain/common/item_ref.dart';
import '../../../domain/wiki/mindmap.dart';
import 'export_keys.dart';
import 'export_sheet.dart';

/// "Export" at the bottom of an info bar, in one row before "Archive" and "Delete".
///
/// For everyone who can read the item: an export takes nothing away and changes
/// nothing.
class InfoExportButton extends StatelessWidget {
  const InfoExportButton({super.key, required this.item, this.drawMindmap});

  final ItemRef item;

  /// How a mind map among the pages is drawn as a picture — handed in by the
  /// screen that draws mind maps; without it, none goes along.
  final MindmapDrawing Function(BuildContext context)? drawMindmap;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: ExportKeys.open,
    onPressed: () => unawaited(
      showExportSheet(context, item: item, drawMindmap: drawMindmap),
    ),
    icon: const Icon(HiwiskiSymbols.download, size: HiwiskiMetrics.icon18),
    label: Text(L.of(context).exportAction),
    style: TextButton.styleFrom(padding: EdgeInsets.zero),
  );
}
