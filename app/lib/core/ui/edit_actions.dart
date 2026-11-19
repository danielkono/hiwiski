import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/hiwiski_metrics.dart';
import 'edit_button.dart';
import 'ui_keys.dart';

/// **One way of editing an item**: "Edit" in its header turns the page itself into
/// its fields, and stands aside for "Cancel" and "Save" in the same place.
///
/// Every item had "Edit" in its header, and each did something else with it: an event
/// opened a dialog, a task only its title, a wiki page its editor with "Save" and no
/// way back, a list a form with its buttons below it. What "Edit" would do, and where
/// it ended, had to be learnt four times.
class EditActions extends StatelessWidget {
  const EditActions({
    super.key,
    required this.editing,
    required this.onEdit,
    required this.onSave,
    required this.onCancel,
  });

  final bool editing;
  final VoidCallback onEdit;

  /// `null` while a save runs: a second tap wrote everything twice.
  final VoidCallback? onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (!editing) return EditButton(onPressed: onEdit);
    final l = L.of(context);
    return Row(
      mainAxisSize: .min,
      spacing: HiwiskiMetrics.space4,
      children: [
        TextButton(
          key: CoreKeys.editCancel,
          onPressed: onCancel,
          child: Text(l.actionCancel),
        ),
        FilledButton(
          key: CoreKeys.editSave,
          onPressed: onSave,
          child: Text(l.actionSave),
        ),
      ],
    );
  }
}
