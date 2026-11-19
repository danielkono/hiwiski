import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../domain/common/item_ref.dart';
import 'export_keys.dart';
import 'export_sheet.dart';

/// "Export" at the bottom of an info bar, in one row before "Archive" and "Delete".
///
/// For everyone who can read the item: an export takes nothing away and changes
/// nothing.
class InfoExportButton extends StatelessWidget {
  const InfoExportButton({super.key, required this.item});

  final ItemRef item;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: ExportKeys.open,
    onPressed: () => unawaited(showExportSheet(context, item: item)),
    icon: const Icon(HiwiskiSymbols.download, size: HiwiskiMetrics.icon18),
    label: Text(L.of(context).exportAction),
    style: TextButton.styleFrom(padding: EdgeInsets.zero),
  );
}
