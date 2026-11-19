import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/undo_snack_bar.dart';

export '../../../core/ui/removable_row.dart';

/// "“Milk” deleted" with "Undo" — after a task was deleted from its row.
void showTodoDeletedSnackBar(
  BuildContext context, {
  required String title,
  required VoidCallback onUndo,
}) => showUndoSnackBar(
  context,
  message: L.of(context).todoDeleted(title),
  onUndo: onUndo,
);

/// "3 ticked-off entries deleted" with "Undo" — after "Delete ticked-off".
void showDoneDeletedSnackBar(
  BuildContext context, {
  required int count,
  required VoidCallback onUndo,
}) => showUndoSnackBar(
  context,
  message: L.of(context).listDoneDeleted(count),
  onUndo: onUndo,
);
