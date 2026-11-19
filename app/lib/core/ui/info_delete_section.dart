import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_symbols.dart';
import '../theme/hiwiski_tokens.dart';

/// **Delete, at the very bottom of the info bar** — the same place on every item.
///
/// It used to sit in a different menu on every screen, next to entries that the info
/// bar already offered a second time (share, history). Asks before it deletes.
class InfoDeleteSection extends StatelessWidget {
  const InfoDeleteSection({
    super.key,
    required this.label,
    required this.onDelete,
    this.confirmTitle,
    this.confirmBody,
    this.besides = const [],
  });

  final String label;

  /// Actions in the same row before "Delete" — "Archive" —, as far apart as the
  /// buttons of the history section.
  final List<Widget> besides;

  /// Runs after the confirmation; without [confirmTitle] it runs right away — for
  /// deletions that ask a question of their own (a series asks which occurrences).
  final AsyncCallback onDelete;
  final String? confirmTitle;
  final String? confirmBody;

  Future<void> _confirm(BuildContext context) async {
    final title = confirmTitle;
    if (title == null) {
      await onDelete();
      return;
    }
    final l = L.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: switch (confirmBody) {
          null => null,
          final body => Text(body),
        },
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final error = context.scheme.error;
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: HiwiskiMetrics.space16,
        crossAxisAlignment: .center,
        children: [
          ...besides,
          TextButton.icon(
            onPressed: () => _confirm(context),
            icon: Icon(
              HiwiskiSymbols.delete,
              size: HiwiskiMetrics.icon18,
              color: error,
            ),
            label: Text(label),
            style: TextButton.styleFrom(
              foregroundColor: error,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}
