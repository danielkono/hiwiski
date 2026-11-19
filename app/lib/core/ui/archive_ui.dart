import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_symbols.dart';
import '../theme/hiwiski_tokens.dart';
import 'ui_keys.dart';
import 'undo_snack_bar.dart';

/// The pieces every archived item shows, the same on a page, a list and a task.
///
/// An archived item opens exactly as before — same screen, same route — and these say
/// what is different: it is kept, read-only, and comes back with one tap.

/// "Archived" next to the title.
class ArchivedChip extends StatelessWidget {
  const ArchivedChip({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Container(
      key: CoreKeys.archivedChip,
      padding: const .symmetric(
        horizontal: HiwiskiMetrics.space8,
        vertical: HiwiskiMetrics.space4,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
      ),
      child: Row(
        mainAxisSize: .min,
        spacing: HiwiskiMetrics.space4,
        children: [
          Icon(
            HiwiskiSymbols.inventory2,
            size: HiwiskiMetrics.icon16,
            color: scheme.onSurfaceVariant,
          ),
          Text(
            L.of(context).archivedMark,
            style: context.texts.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Archived." with "Undo" — after archiving from the item itself. It goes by itself
/// like every "Undo" note: with an action, Flutter kept it standing until it was
/// dismissed.
void showArchivedSnackBar(
  BuildContext context, {
  required VoidCallback onUndo,
}) => showUndoSnackBar(
  context,
  message: L.of(context).archiveDone,
  onUndo: onUndo,
);

/// "Only this page" or "With its 4 subpages" — `null` when cancelled.
///
/// Asked only when there are subpages to take along; a single page is archived or
/// restored without a question.
Future<bool?> askWithSubpages(
  BuildContext context, {
  required int subpages,
  required bool restore,
}) {
  final l = L.of(context);
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(restore ? l.archiveRestorePageTitle : l.archivePageTitle),
      content: Text(
        restore
            ? l.archiveRestorePageBody(subpages)
            : l.archivePageBody(subpages),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        TextButton(
          key: CoreKeys.archiveOnlyThis,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.archiveOnlyThisPage),
        ),
        FilledButton(
          key: CoreKeys.archiveWithSubpages,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.archiveWithSubpages(subpages)),
        ),
      ],
    ),
  );
}
