import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_symbols.dart';
import 'ui_keys.dart';

/// "Archive …" at the bottom of an info bar, in one row with "Delete"
/// (`InfoDeleteSection.besides`).
///
/// No confirmation: archiving deletes nothing and is undone with one tap — the snackbar
/// after it offers exactly that.
class InfoArchiveButton extends StatelessWidget {
  const InfoArchiveButton({
    super.key,
    required this.label,
    required this.onArchive,
  });

  final String label;
  final AsyncCallback onArchive;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: CoreKeys.archiveAction,
      onPressed: () => unawaited(onArchive()),
      icon: const Icon(HiwiskiSymbols.inventory2, size: HiwiskiMetrics.icon18),
      label: Text(label),
      style: TextButton.styleFrom(padding: EdgeInsets.zero),
    );
  }
}
